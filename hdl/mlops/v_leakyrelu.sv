`timescale 1ps/1ps
`default_nettype none
// prevents system from inferring an undeclared logic (good practice)

module v_leakyrelu
#(  parameter InVecLength,
    parameter NBits,
    parameter WorkingRegs ) (
    input wire clk_in,
    input wire rst_in,
    input wire in_data_ready,
    input wire signed [WorkingRegs-1:0][NBits-1:0] in_data,
    output logic signed [WorkingRegs-1:0][NBits-1:0] write_out_data,
    output logic req_chunk_in,
    output logic req_chunk_out,
    output logic out_vector_valid
);

typedef enum logic {WAITING, PROCESSING} relu_state;
relu_state state;
logic signed [WorkingRegs-1:0][3:0] working_regs;
// assumes single-cycle fifo
logic [$clog2(InVecLength):0] vec_in_idx;
logic [$clog2(InVecLength):0] vec_out_idx; // InVecLength = OutVecLength, one-to-one map
logic vec_op_complete;

always_comb begin
  vec_op_complete = vec_out_idx == 0;
  foreach(working_regs[i]) working_regs[i] = $signed(in_data[i])>>8;
  foreach(write_out_data[i]) write_out_data[i] = $signed(working_regs[i]) < 0 ?  $signed(in_data[i]) >>> 7: //ReLU with 128 leak factor
                                                                                  in_data[i];
end

always_ff @(posedge clk_in) begin
  if(~rst_in) begin // axi standard reset active low
    vec_in_idx <= 0;
    vec_out_idx <= WorkingRegs;
    state <= WAITING;
    req_chunk_in <= 0;
    req_chunk_out <= 0;
  end else begin
    if(state == WAITING) begin
        if(in_data_ready) begin
          vec_in_idx <= WorkingRegs >= InVecLength ? 0: WorkingRegs;
          vec_out_idx <= WorkingRegs >= InVecLength ? 0: WorkingRegs;
          req_chunk_out <= 1;
          req_chunk_in <= WorkingRegs < InVecLength;
          state <= PROCESSING;
        end else begin
          vec_out_idx <= WorkingRegs;
          req_chunk_in <= 0;
          req_chunk_out <= 0;
        end
    end else if (state == PROCESSING) begin
      vec_in_idx <= vec_in_idx + WorkingRegs >= InVecLength ? 0 : vec_in_idx + WorkingRegs;
      if(vec_op_complete) begin
        req_chunk_out <= in_data_ready;
        vec_out_idx <= WorkingRegs;
        req_chunk_in <= in_data_ready;
        state <= in_data_ready ? PROCESSING : WAITING;
      end else begin
        req_chunk_in <= 1;
        req_chunk_out <= 1;
        vec_out_idx <= vec_out_idx + WorkingRegs >= InVecLength ? 0 : vec_out_idx + WorkingRegs;
      end
    end
  end
end

assign out_vector_valid = vec_out_idx == 0;

endmodule;
`default_nettype wire