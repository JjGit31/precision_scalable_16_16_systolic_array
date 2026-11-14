`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2026 17:12:02
// Design Name: 
// Module Name: actual_adder
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



`timescale 1ns / 1ps
`default_nettype none

// =============================================================
// 8-BIT CARRY LOOKAHEAD ADDER
// =============================================================
module cla_8bit (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire       cin,
    output wire [7:0] sum,
    output wire       cout
);

    wire [7:0] g, p;
    wire [8:0] c;

    assign g = a & b;
    assign p = a ^ b;

    assign c[0] = cin;
    assign c[1] = g[0] | (p[0] & c[0]);
    assign c[2] = g[1] | (p[1] & g[0]) |
                  (p[1] & p[0] & c[0]);
    assign c[3] = g[2] | (p[2] & g[1]) |
                  (p[2] & p[1] & g[0]) |
                  (p[2] & p[1] & p[0] & c[0]);
    assign c[4] = g[3] | (p[3] & g[2]) |
                  (p[3] & p[2] & g[1]) |
                  (p[3] & p[2] & p[1] & g[0]) |
                  (p[3] & p[2] & p[1] & p[0] & c[0]);
    assign c[5] = g[4] | (p[4] & g[3]) |
                  (p[4] & p[3] & g[2]) |
                  (p[4] & p[3] & p[2] & g[1]) |
                  (p[4] & p[3] & p[2] & p[1] & g[0]) |
                  (p[4] & p[3] & p[2] & p[1] & p[0] & c[0]);
    assign c[6] = g[5] | (p[5] & g[4]) |
                  (p[5] & p[4] & g[3]) |
                  (p[5] & p[4] & p[3] & g[2]) |
                  (p[5] & p[4] & p[3] & p[2] & g[1]) |
                  (p[5] & p[4] & p[3] & p[2] & p[1] & g[0]) |
                  (p[5] & p[4] & p[3] & p[2] & p[1] & p[0] & c[0]);
    assign c[7] = g[6] | (p[6] & g[5]) |
                  (p[6] & p[5] & g[4]) |
                  (p[6] & p[5] & p[4] & g[3]) |
                  (p[6] & p[5] & p[4] & p[3] & g[2]) |
                  (p[6] & p[5] & p[4] & p[3] & p[2] & g[1]) |
                  (p[6] & p[5] & p[4] & p[3] & p[2] & p[1] & g[0]) |
                  (p[6] & p[5] & p[4] & p[3] & p[2] & p[1] & p[0] & c[0]);
    assign c[8] = g[7] | (p[7] & g[6]) |
                  (p[7] & p[6] & g[5]) |
                  (p[7] & p[6] & p[5] & g[4]) |
                  (p[7] & p[6] & p[5] & p[4] & g[3]) |
                  (p[7] & p[6] & p[5] & p[4] & p[3] & g[2]) |
                  (p[7] & p[6] & p[5] & p[4] & p[3] & p[2] & g[1]) |
                  (p[7] & p[6] & p[5] & p[4] & p[3] & p[2] & p[1] & g[0]) |
                  (p[7] & p[6] & p[5] & p[4] & p[3] & p[2] & p[1] & p[0] & c[0]);

    assign sum  = p ^ c[7:0];
    assign cout = c[8];

endmodule

// =============================================================
// LATCH-BASED GLITCH-FREE CLOCK GATING
// =============================================================
module icg_cell (
    input  wire clk,
    input  wire en,
    output wire gclk
);

    reg en_latched;

    always @(clk or en) begin
        if (!clk)
            en_latched = en;
    end

    assign gclk = clk & en_latched;

endmodule

// =============================================================
// ACTUAL ADDER - SYSTOLIC ARRAY COMPATIBLE
//
// mode 00 = INT4  -> 12 accumulator bits
// mode 01 = INT8  -> 20 accumulator bits
// mode 10 = INT16 -> 36 accumulator bits
//
// mac_en      : valid operand pair
// prod_signed : product requires sign extension
//
// Retains 4 x 8-bit CLA and upper correction network.
// =============================================================
module actual_adder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clr,
    input  wire        mac_en,
    input  wire [1:0]  mode,
    input  wire        prod_signed,
    input  wire [31:0] prod_in,
    output wire [35:0] acc_out
);

    reg [3:0] acc_b0, acc_b1, acc_b2;
    reg [3:0] acc_b3, acc_b4;
    reg [3:0] acc_b5, acc_b6, acc_b7, acc_b8;

    wire [35:0] acc_reg;
    wire [35:0] acc_feedback;

    assign acc_reg = {
        acc_b8, acc_b7, acc_b6,
        acc_b5, acc_b4, acc_b3,
        acc_b2, acc_b1, acc_b0
    };

    assign acc_feedback = clr ? 36'b0 : acc_reg;

    // ---------------------------------------------------------
    // Operand isolation and carry gating
    // ---------------------------------------------------------
    wire is_int4  = (mode == 2'b00);
    wire is_int8  = (mode == 2'b01);
    wire is_int16 = (mode == 2'b10);
    wire mode_valid = is_int4 | is_int8 | is_int16;

    wire pass8  = is_int8 | is_int16;
    wire pass16 = is_int16;
    wire pass24 = is_int16;

    wire [7:0] slice1_a =
        pass8 ? acc_feedback[15:8] : 8'h00;
    wire [7:0] slice1_b =
        pass8 ? prod_in[15:8] : 8'h00;

    wire [7:0] slice2_a =
        pass16 ? acc_feedback[23:16] : 8'h00;
    wire [7:0] slice2_b =
        pass16 ? prod_in[23:16] : 8'h00;

    wire [7:0] slice3_a =
        pass24 ? acc_feedback[31:24] : 8'h00;
    wire [7:0] slice3_b =
        pass24 ? prod_in[31:24] : 8'h00;

    wire [7:0] sum0, sum1, sum2, sum3;
    wire cout0, cout1, cout2, cout3;
    wire c8, c16, c24;

    cla_8bit slice0 (
        .a(acc_feedback[7:0]),
        .b(prod_in[7:0]),
        .cin(1'b0),
        .sum(sum0),
        .cout(cout0)
    );

    assign c8 = cout0;

    cla_8bit slice1 (
        .a(slice1_a),
        .b(slice1_b),
        .cin(c8 & pass8),
        .sum(sum1),
        .cout(cout1)
    );

    assign c16 = cout1;

    cla_8bit slice2 (
        .a(slice2_a),
        .b(slice2_b),
        .cin(c16 & pass16),
        .sum(sum2),
        .cout(cout2)
    );

    assign c24 = cout2;

    cla_8bit slice3 (
        .a(slice3_a),
        .b(slice3_b),
        .cin(c24 & pass24),
        .sum(sum3),
        .cout(cout3)
    );

    wire c32_out = cout3;

    wire [31:0] cla_sum =
        {sum3, sum2, sum1, sum0};

    // ---------------------------------------------------------
    // Upper 4-bit sign/carry correction
    // ---------------------------------------------------------
    reg       csel;
    reg       ssel;
    reg [3:0] Hsel;

    always @(*) begin
        case (mode)
            2'b00: begin
                csel = c8;
                ssel = prod_signed & prod_in[7];
                Hsel = acc_feedback[11:8];
            end

            2'b01: begin
                csel = c16;
                ssel = prod_signed & prod_in[15];
                Hsel = acc_feedback[19:16];
            end

            2'b10: begin
                csel = c32_out;
                ssel = prod_signed & prod_in[31];
                Hsel = acc_feedback[35:32];
            end

            default: begin
                csel = 1'b0;
                ssel = 1'b0;
                Hsel = 4'b0000;
            end
        endcase
    end

    wire E = csel ^ ssel;

    wire [3:0] M;
    assign M[0] = ~(Hsel[0] ^ csel);
    assign M[1] = ~(Hsel[1] ^ csel);
    assign M[2] = ~(Hsel[2] ^ csel);
    assign M[3] = ~(Hsel[3] ^ csel);

    wire [3:0] T;
    assign T[0] = E;
    assign T[1] = T[0] & M[0];
    assign T[2] = T[1] & M[1];
    assign T[3] = T[2] & M[2];

    wire [3:0] upper_corrected;
    assign upper_corrected = Hsel ^ T;

    // ---------------------------------------------------------
    // Assemble precision-dependent accumulator result
    // ---------------------------------------------------------
    wire [35:0] total_result;

    assign total_result =
        is_int4  ? {24'h0, upper_corrected, cla_sum[7:0]} :
        is_int8  ? {16'h0, upper_corrected, cla_sum[15:0]} :
        is_int16 ? {upper_corrected, cla_sum[31:0]} :
                   acc_reg;

    // ---------------------------------------------------------
    // Nine 4-bit clock-gated accumulator groups
    // ---------------------------------------------------------
    wire [8:0] block_clk_en;
    wire [8:0] icg_en;
    wire [8:0] gclk;

    assign block_clk_en[0] = mode_valid;
    assign block_clk_en[1] = mode_valid;
    assign block_clk_en[2] = mode_valid;

    assign block_clk_en[3] = pass8;
    assign block_clk_en[4] = pass8;

    assign block_clk_en[5] = is_int16;
    assign block_clk_en[6] = is_int16;
    assign block_clk_en[7] = is_int16;
    assign block_clk_en[8] = is_int16;

    // Critical change:
    // Accumulate only during valid PE operations.
    // Allow all groups to clock during accumulator clear.
    assign icg_en =
        ({9{mac_en}} & block_clk_en) | {9{clr}};

    genvar i;
    generate
        for (i = 0; i < 9; i = i + 1) begin : GEN_ICG
            icg_cell u_icg (
                .clk(clk),
                .en(icg_en[i]),
                .gclk(gclk[i])
            );
        end
    endgenerate

    // ---------------------------------------------------------
    // Clock-gated accumulator registers
    // ---------------------------------------------------------
    always @(posedge gclk[0] or negedge rst_n) begin
        if (!rst_n) acc_b0 <= 4'b0;
        else if (clr) acc_b0 <= 4'b0;
        else acc_b0 <= total_result[3:0];
    end

    always @(posedge gclk[1] or negedge rst_n) begin
        if (!rst_n) acc_b1 <= 4'b0;
        else if (clr) acc_b1 <= 4'b0;
        else acc_b1 <= total_result[7:4];
    end

    always @(posedge gclk[2] or negedge rst_n) begin
        if (!rst_n) acc_b2 <= 4'b0;
        else if (clr) acc_b2 <= 4'b0;
        else acc_b2 <= total_result[11:8];
    end

    always @(posedge gclk[3] or negedge rst_n) begin
        if (!rst_n) acc_b3 <= 4'b0;
        else if (clr) acc_b3 <= 4'b0;
        else acc_b3 <= total_result[15:12];
    end

    always @(posedge gclk[4] or negedge rst_n) begin
        if (!rst_n) acc_b4 <= 4'b0;
        else if (clr) acc_b4 <= 4'b0;
        else acc_b4 <= total_result[19:16];
    end

    always @(posedge gclk[5] or negedge rst_n) begin
        if (!rst_n) acc_b5 <= 4'b0;
        else if (clr) acc_b5 <= 4'b0;
        else acc_b5 <= total_result[23:20];
    end

    always @(posedge gclk[6] or negedge rst_n) begin
        if (!rst_n) acc_b6 <= 4'b0;
        else if (clr) acc_b6 <= 4'b0;
        else acc_b6 <= total_result[27:24];
    end

    always @(posedge gclk[7] or negedge rst_n) begin
        if (!rst_n) acc_b7 <= 4'b0;
        else if (clr) acc_b7 <= 4'b0;
        else acc_b7 <= total_result[31:28];
    end

    always @(posedge gclk[8] or negedge rst_n) begin
        if (!rst_n) acc_b8 <= 4'b0;
        else if (clr) acc_b8 <= 4'b0;
        else acc_b8 <= total_result[35:32];
    end

    assign acc_out = acc_reg;

endmodule

`default_nettype wire

