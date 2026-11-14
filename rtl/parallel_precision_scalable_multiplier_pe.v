`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2026 15:13:45
// Design Name: 
// Module Name: parallel_precision_scalable_multiplier_pe
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

// ============================================================
// Precision-scalable multiplier
// INT4, INT8, INT16
// All required helper modules included in this file.
// ============================================================

module full_adder(
    input wire A,
    input wire B,
    input wire CIN,
    output wire SUM,
    output wire CARRY
);
    assign SUM = A ^ B ^ CIN;
    assign CARRY = (A & B) | (A & CIN) | (B & CIN);
endmodule


module mul5_5(
    input wire [4:0] A,
    input wire [4:0] B,
    output wire [8:0] SUM
);
    wire pp00, pp01, pp02, pp03, pp04;
    wire pp10, pp11, pp12, pp13, pp14;
    wire pp20, pp21, pp22, pp23, pp24;
    wire pp30, pp31, pp32, pp33, pp34;
    wire pp40, pp41, pp42, pp43, pp44;

    assign pp00 = A[0] & B[0];
    assign pp01 = A[0] & B[1];
    assign pp02 = A[0] & B[2];
    assign pp03 = A[0] & B[3];
    assign pp04 = ~(A[0] & B[4]);

    assign pp10 = A[1] & B[0];
    assign pp11 = A[1] & B[1];
    assign pp12 = A[1] & B[2];
    assign pp13 = A[1] & B[3];
    assign pp14 = ~(A[1] & B[4]);

    assign pp20 = A[2] & B[0];
    assign pp21 = A[2] & B[1];
    assign pp22 = A[2] & B[2];
    assign pp23 = A[2] & B[3];
    assign pp24 = ~(A[2] & B[4]);

    assign pp30 = A[3] & B[0];
    assign pp31 = A[3] & B[1];
    assign pp32 = A[3] & B[2];
    assign pp33 = A[3] & B[3];
    assign pp34 = ~(A[3] & B[4]);

    assign pp40 = ~(A[4] & B[0]);
    assign pp41 = ~(A[4] & B[1]);
    assign pp42 = ~(A[4] & B[2]);
    assign pp43 = ~(A[4] & B[3]);
    assign pp44 = A[4] & B[4];

    wire [21:0] TS;
    wire [21:0] TC;

    assign TS[0] = pp00;
    assign TC[0] = 1'b0;
    assign TC[9] = 1'b0;
    assign TS[9] = ~TC[8];

    full_adder fa0 (
        pp01, pp10, 1'b0, TS[1], TC[1]
    );
    full_adder fa1 (
        pp20, TS[10], TC[1], TS[2], TC[2]
    );
    full_adder fa2 (
        TC[2], TS[12], TC[10], TS[3], TC[3]
    );
    full_adder fa3 (
        TC[3], TS[15], TC[12], TS[4], TC[4]
    );
    full_adder fa4 (
        TC[4], TS[18], TC[15], TS[5], TC[5]
    );
    full_adder fa5 (
        TC[5], TS[20], TC[18], TS[6], TC[6]
    );
    full_adder fa6 (
        TC[6], TS[21], TC[20], TS[7], TC[7]
    );
    full_adder fa7 (
        TC[7], pp44, TC[21], TS[8], TC[8]
    );

    full_adder fa8 (
        pp02, pp11, 1'b0, TS[10], TC[10]
    );
    full_adder fa9 (
        pp30, pp21, 1'b0, TS[11], TC[11]
    );
    full_adder fa10 (
        pp12, pp03, TS[11], TS[12], TC[12]
    );
    full_adder fa11 (
        pp04, pp13, 1'b0, TS[13], TC[13]
    );
    full_adder fa12 (
        pp22, pp31, TS[13], TS[14], TC[14]
    );
    full_adder fa13 (
        pp40, TC[11], TS[14], TS[15], TC[15]
    );
    full_adder fa14 (
        pp14, pp23, pp32, TS[16], TC[16]
    );
    full_adder fa15 (
        pp41, TS[16], TC[13], TS[17], TC[17]
    );
    full_adder fa16 (
        TS[17], 1'b1, TC[14], TS[18], TC[18]
    );
    full_adder fa17 (
        pp24, pp33, TC[16], TS[19], TC[19]
    );
    full_adder fa18 (
        pp42, TS[19], TC[17], TS[20], TC[20]
    );
    full_adder fa19 (
        pp34, pp43, TC[19], TS[21], TC[21]
    );

    assign SUM = TS[8:0];
endmodule


module csa17_custom(
    input wire [16:0] a,
    input wire [16:0] b,
    input wire [16:0] c,
    output wire [16:0] sum,
    output wire [16:0] carry
);
    wire [16:0] carry_raw;

    genvar i;
    generate
        for (i=0; i<17; i=i+1) begin: g_fa
            full_adder fa (
                .A(a[i]),
                .B(b[i]),
                .CIN(c[i]),
                .SUM(sum[i]),
                .CARRY(carry_raw[i])
            );
        end
    endgenerate

    assign carry = {carry_raw[15:0], 1'b0};
endmodule


module ripple_adder17_custom(
    input wire [16:0] a,
    input wire [16:0] b,
    output wire [16:0] sum
);
    wire [17:0] c;
    assign c[0] = 1'b0;

    genvar i;
    generate
        for (i=0; i<17; i=i+1) begin: g_fa
            full_adder fa (
                .A(a[i]),
                .B(b[i]),
                .CIN(c[i]),
                .SUM(sum[i]),
                .CARRY(c[i+1])
            );
        end
    endgenerate
endmodule


module mul8_tile17_custom(
    input wire [4:0] A1,
    input wire [4:0] B1,
    input wire [4:0] A2,
    input wire [4:0] B2,
    input wire [4:0] A3,
    input wire [4:0] B3,
    input wire [4:0] A4,
    input wire [4:0] B4,

    input wire mode4,
    input wire mode8,

    output wire [16:0] R
);
    wire [8:0] p_a, p_b, p_c, p_d;

    mul5_5 core_A (
        .A(A1), .B(B1), .SUM(p_a)
    );
    mul5_5 core_B (
        .A(A2), .B(B2), .SUM(p_b)
    );
    mul5_5 core_C (
        .A(A3), .B(B3), .SUM(p_c)
    );
    mul5_5 core_D (
        .A(A4), .B(B4), .SUM(p_d)
    );

    wire [8:0] p_b_flip = p_b ^ 9'h100;
    wire [8:0] p_c_flip = p_c ^ 9'h100;
    wire [8:0] p_d_flip = p_d ^ 9'h100;

    wire [16:0] row_a =
        mode8 ? {9'b0, p_a[7:0]} : 17'b0;

    wire [16:0] row_b =
        mode8 ? {4'b0, p_b_flip, 4'b0} : 17'b0;

    wire [16:0] row_c =
        mode8 ? {4'b0, p_c_flip, 4'b0} : 17'b0;

    wire [16:0] row_d =
        mode8 ? {p_d_flip, 8'b0} : 17'b0;

    wire [16:0] row_k =
        mode8 ? 17'h0E000 : 17'b0;

    wire [16:0] s1, c1, s2, c2, s3, c3;
    wire [16:0] sum17;

    csa17_custom csa1 (
        .a(row_a),
        .b(row_b),
        .c(row_c),
        .sum(s1),
        .carry(c1)
    );

    csa17_custom csa2 (
        .a(s1),
        .b(c1),
        .c(row_d),
        .sum(s2),
        .carry(c2)
    );

    csa17_custom csa3 (
        .a(s2),
        .b(c2),
        .c(row_k),
        .sum(s3),
        .carry(c3)
    );

    ripple_adder17_custom final_adder (
        .a(s3),
        .b(c3),
        .sum(sum17)
    );

    assign R =
        mode4 ? {{8{p_a[8]}}, p_a} :
        mode8 ? sum17 :
        17'b0;
endmodule


module mul8_operand_tile_parallel(
    input wire [7:0] A,
    input wire [7:0] B,
    input wire sx,
    input wire sy,
    input wire enable,
    input wire mode4,
    output wire [16:0] R
);
    wire en4 = enable & mode4;
    wire en8 = enable & ~mode4;

    wire [4:0] A1 =
        en4 ? {(sx & A[3]), A[3:0]} :
        en8 ? {1'b0, A[3:0]} : 5'b0;

    wire [4:0] B1 =
        en4 ? {(sy & B[3]), B[3:0]} :
        en8 ? {1'b0, B[3:0]} : 5'b0;

    wire [4:0] A2 =
        en8 ? {1'b0, A[3:0]} : 5'b0;

    wire [4:0] B2 =
        en8 ? {(sy & B[7]), B[7:4]} : 5'b0;

    wire [4:0] A3 =
        en8 ? {(sx & A[7]), A[7:4]} : 5'b0;

    wire [4:0] B3 =
        en8 ? {1'b0, B[3:0]} : 5'b0;

    wire [4:0] A4 =
        en8 ? {(sx & A[7]), A[7:4]} : 5'b0;

    wire [4:0] B4 =
        en8 ? {(sy & B[7]), B[7:4]} : 5'b0;

    mul8_tile17_custom u_tile (
        .A1(A1), .B1(B1),
        .A2(A2), .B2(B2),
        .A3(A3), .B3(B3),
        .A4(A4), .B4(B4),
        .mode4(en4),
        .mode8(en8),
        .R(R)
    );
endmodule


module csa32_parallel(
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [31:0] c,
    output wire [31:0] sum,
    output wire [31:0] carry
);
    wire [31:0] carry_raw;

    genvar i;
    generate
        for (i=0; i<32; i=i+1) begin: g_csa
            full_adder fa (
                .A(a[i]),
                .B(b[i]),
                .CIN(c[i]),
                .SUM(sum[i]),
                .CARRY(carry_raw[i])
            );
        end
    endgenerate

    assign carry = {carry_raw[30:0], 1'b0};
endmodule


module ripple_adder32_custom(
    input wire [31:0] a,
    input wire [31:0] b,
    output wire [31:0] sum
);
    wire [32:0] c;
    assign c[0] = 1'b0;

    genvar k;
    generate
        for (k=0; k<32; k=k+1) begin: g_final_fa
            full_adder fa (
                .A(a[k]),
                .B(b[k]),
                .CIN(c[k]),
                .SUM(sum[k]),
                .CARRY(c[k+1])
            );
        end
    endgenerate
endmodule


// ============================================================
// MAIN MODULE
// Precision-scalable multiplier for ONE PE
// ============================================================

module parallel_precision_scalable_multiplier_pe(
    input wire [1:0] mode,
    input wire signed_x,
    input wire signed_y,

    input wire [15:0] X,
    input wire [15:0] Y,

    output wire [31:0] result,
    output wire result_signed
);
    localparam MODE_4X4   = 2'b00;
    localparam MODE_8X8   = 2'b01;
    localparam MODE_16X16 = 2'b10;

    wire is4  = (mode == MODE_4X4);
    wire is8  = (mode == MODE_8X8);
    wire is16 = (mode == MODE_16X16);

    wire [16:0] r_ll, r_hl, r_lh, r_hh;

    mul8_operand_tile_parallel u_tile_ll (
        .A(X[7:0]),
        .B(Y[7:0]),
        .sx(is16 ? 1'b0 : signed_x),
        .sy(is16 ? 1'b0 : signed_y),
        .enable(is4 | is8 | is16),
        .mode4(is4),
        .R(r_ll)
    );

    mul8_operand_tile_parallel u_tile_hl (
        .A(X[15:8]),
        .B(Y[7:0]),
        .sx(signed_x),
        .sy(1'b0),
        .enable(is16),
        .mode4(1'b0),
        .R(r_hl)
    );

    mul8_operand_tile_parallel u_tile_lh (
        .A(X[7:0]),
        .B(Y[15:8]),
        .sx(1'b0),
        .sy(signed_y),
        .enable(is16),
        .mode4(1'b0),
        .R(r_lh)
    );

    mul8_operand_tile_parallel u_tile_hh (
        .A(X[15:8]),
        .B(Y[15:8]),
        .sx(signed_x),
        .sy(signed_y),
        .enable(is16),
        .mode4(1'b0),
        .R(r_hh)
    );

    wire [16:0] r_hl_xor =
        {~r_hl[16], r_hl[15:0]};

    wire [16:0] r_lh_xor =
        {~r_lh[16], r_lh[15:0]};

    wire [31:0] term_ll =
        is16 ? {15'b0, r_ll} : 32'b0;

    wire [31:0] term_hl =
        is16 ? ({15'b0, r_hl_xor} << 8) : 32'b0;

    wire [31:0] term_lh =
        is16 ? ({15'b0, r_lh_xor} << 8) : 32'b0;

    wire [31:0] term_hh =
        is16 ? {r_hh[15:0], 16'b0} : 32'b0;

    wire [31:0] k_acc =
        is16 ? 32'hFE000000 : 32'b0;

    wire [31:0] s1, c1, s2, c2, s3, c3;

    csa32_parallel csa_top_1 (
        .a(term_ll),
        .b(term_hl),
        .c(term_lh),
        .sum(s1),
        .carry(c1)
    );

    csa32_parallel csa_top_2 (
        .a(s1),
        .b(c1),
        .c(term_hh),
        .sum(s2),
        .carry(c2)
    );

    csa32_parallel csa_top_3 (
        .a(s2),
        .b(c2),
        .c(k_acc),
        .sum(s3),
        .carry(c3)
    );

    wire [31:0] product_16;

    ripple_adder32_custom final_adder_16 (
        .a(s3),
        .b(c3),
        .sum(product_16)
    );

    assign result =
        (is4 | is8) ? {{15{r_ll[16]}}, r_ll} :
        is16 ? product_16 :
        32'b0;

    assign result_signed =
        (is4 | is8 | is16) &
        (signed_x | signed_y);

endmodule
