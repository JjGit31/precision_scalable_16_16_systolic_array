`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2026 15:12:33
// Design Name: 
// Module Name: precision_scalable_mac_pe_en
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
/////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
`default_nettype none

// ============================================================
// PRECISION-SCALABLE MAC PROCESSING ELEMENT
//
// 16x16 output-stationary systolic array
//
// Multiplier : Existing precision-scalable multiplier
// Accumulator: actual_adder (clock-gated)
//
// Precision modes:
//   00 = INT4
//   01 = INT8
//   10 = INT16
//
// The systolic array instantiates this module 256 times.
// ============================================================

module precision_scalable_mac_pe_en (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clr,
    input  wire        mac_en,

    input  wire [1:0]  mode,
    input  wire        signed_x,
    input  wire        signed_y,

    input  wire [15:0] X,
    input  wire [15:0] Y,

    output wire [31:0] product,
    output wire        product_signed,
    output wire [35:0] accumulator
);

    // ========================================================
    // 1. EXISTING PRECISION-SCALABLE MULTIPLIER
    // ========================================================

    parallel_precision_scalable_multiplier_pe u_multiplier (
        .mode          (mode),
        .signed_x      (signed_x),
        .signed_y      (signed_y),
        .X             (X),
        .Y             (Y),
        .result        (product),
        .result_signed (product_signed)
    );

    // ========================================================
    // 2. NEW CLOCK-GATED ACTUAL ADDER ACCUMULATOR
    // ========================================================

    actual_adder u_accumulator (
        .clk         (clk),
        .rst_n       (rst_n),
        .clr         (clr),
        .mac_en      (mac_en),
        .mode        (mode),
        .prod_signed (product_signed),
        .prod_in     (product),
        .acc_out     (accumulator)
    );

endmodule

`default_nettype wire


