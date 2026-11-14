`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2026 15:10:16
// Design Name: 
// Module Name: precision_packed_systolic_array
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



`timescale 1ns/1ps
`default_nettype none

module precision_packed_systolic_array #(
    parameter PE_N = 16,
    parameter COUNT_W = $clog2(PE_N + 2*(PE_N/4) - 1)
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    input wire [1:0] precision_mode,
    input wire signed_a,
    input wire signed_b,

    input wire [(PE_N/4)*64-1:0] a_left_data,
    input wire [(PE_N/4)-1:0] a_left_valid,

    input wire [(PE_N/4)*64-1:0] b_top_data,
    input wire [(PE_N/4)-1:0] b_top_valid,

    output wire busy,
    output wire done,

    output wire [1:0] active_mode,
    output wire active_signed_a,
    output wire active_signed_b,

    output wire [COUNT_W-1:0] cycle_count,
    output wire [1:0] state_debug,

    output wire [PE_N*PE_N*36-1:0] c_flat
);

    localparam GRID = PE_N/4;
    localparam LAST_CYCLE = PE_N + 2*GRID - 2;

    localparam S_IDLE = 2'd0;
    localparam S_CLEAR = 2'd1;
    localparam S_COMPUTE = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0] state_q;
    reg [1:0] mode_q;
    reg signed_a_q;
    reg signed_b_q;
    reg [COUNT_W-1:0] cycle_count_q;

    wire clear_acc;
    wire compute_en;

    wire [63:0] a_link [0:GRID-1][0:GRID-1];
    wire [63:0] b_link [0:GRID-1][0:GRID-1];

    wire a_v_link [0:GRID-1][0:GRID-1];
    wire b_v_link [0:GRID-1][0:GRID-1];

    wire [575:0] c_tile [0:GRID-1][0:GRID-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            mode_q <= 2'b00;
            signed_a_q <= 1'b0;
            signed_b_q <= 1'b0;
            cycle_count_q <= {COUNT_W{1'b0}};
        end
        else begin
            case (state_q)

                S_IDLE: begin
                    cycle_count_q <= 0;

                    if (start && precision_mode != 2'b11) begin
                        mode_q <= precision_mode;
                        signed_a_q <= signed_a;
                        signed_b_q <= signed_b;
                        state_q <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    cycle_count_q <= 0;
                    state_q <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    if (cycle_count_q == LAST_CYCLE)
                        state_q <= S_DONE;
                    else
                        cycle_count_q <= cycle_count_q + 1'b1;
                end

                S_DONE: begin
                    if (!start)
                        state_q <= S_IDLE;
                end

                default: begin
                    state_q <= S_IDLE;
                    cycle_count_q <= 0;
                end
            endcase
        end
    end

    assign clear_acc = (state_q == S_CLEAR);
    assign compute_en = (state_q == S_COMPUTE);

    assign busy = (state_q == S_CLEAR) ||
                  (state_q == S_COMPUTE);

    assign done = (state_q == S_DONE);

    assign active_mode = mode_q;
    assign active_signed_a = signed_a_q;
    assign active_signed_b = signed_b_q;

    assign cycle_count = cycle_count_q;
    assign state_debug = state_q;

    genvar tr, tc, lr, lc;

    generate
        for (tr=0; tr<GRID; tr=tr+1) begin: ROW

            for (tc=0; tc<GRID; tc=tc+1) begin: COL

                wire [63:0] a_raw;
                wire [63:0] b_raw;

                wire a_valid_raw;
                wire b_valid_raw;

                wire [63:0] a_tile_in;
                wire [63:0] b_tile_in;

                wire a_tile_valid;
                wire b_tile_valid;

                wire [3:0] bank_enable_unused;

                // A flows from left to right.
                if (tc == 0) begin: A_BOUNDARY
                    assign a_raw =
                        a_left_data[tr*64 +: 64];

                    assign a_valid_raw =
                        a_left_valid[tr];
                end
                else begin: A_FROM_LEFT
                    assign a_raw =
                        a_link[tr][tc-1];

                    assign a_valid_raw =
                        a_v_link[tr][tc-1];
                end

                // B flows from top to bottom.
                if (tr == 0) begin: B_BOUNDARY
                    assign b_raw =
                        b_top_data[tc*64 +: 64];

                    assign b_valid_raw =
                        b_top_valid[tc];
                end
                else begin: B_FROM_ABOVE
                    assign b_raw =
                        b_link[tr-1][tc];

                    assign b_valid_raw =
                        b_v_link[tr-1][tc];
                end

                assign a_tile_valid =
                    compute_en && a_valid_raw;

                assign b_tile_valid =
                    compute_en && b_valid_raw;

                assign a_tile_in =
                    a_tile_valid ? a_raw : 64'd0;

                assign b_tile_in =
                    b_tile_valid ? b_raw : 64'd0;

                precision_packed_tile_4x4 u_tile (
                    .clk(clk),
                    .rst_n(rst_n),

                    .clear_acc(clear_acc),
                    .compute_en(compute_en),

                    .precision_mode(mode_q),
                    .signed_a(signed_a_q),
                    .signed_b(signed_b_q),

                    .a_in(a_tile_in),
                    .a_valid_in(a_tile_valid),
                    .a_out(a_link[tr][tc]),
                    .a_valid_out(a_v_link[tr][tc]),

                    .b_in(b_tile_in),
                    .b_valid_in(b_tile_valid),
                    .b_out(b_link[tr][tc]),
                    .b_valid_out(b_v_link[tr][tc]),

                    .c_tile(c_tile[tr][tc]),
                    .bank_capture_en(bank_enable_unused)
                );

                // Map local 4x4 outputs to global C.
                for (lr=0; lr<4; lr=lr+1) begin: OUT_ROW

                    for (lc=0; lc<4; lc=lc+1) begin: OUT_COL

                        localparam GLOBAL_ROW = tr*4 + lr;
                        localparam GLOBAL_COL = tc*4 + lc;

                        localparam LOCAL_PE = lr*4 + lc;

                        localparam C_LSB =
                            (GLOBAL_ROW*PE_N + GLOBAL_COL)*36;

                        assign c_flat[C_LSB +: 36] =
                            c_tile[tr][tc][LOCAL_PE*36 +: 36];

                    end
                end

            end
        end
    endgenerate

endmodule

`default_nettype wire

