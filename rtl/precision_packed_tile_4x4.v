`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.11.2026 15:11:41
// Design Name: 
// Module Name: precision_packed_tile_4x4
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

// ================================================================
// 4x4 PRECISION-SCALABLE SYSTOLIC MACROBLOCK
//
// 4 rows x 4 columns = 16 processing elements
//
// A input: four packed operands across 64 bits
// B input: four packed operands across 64 bits
//
// Precision modes:
//   00 = INT4
//   01 = INT8
//   10 = INT16
//
// Clock gating:
//   Four separate 16-bit A banks
//   Four separate 16-bit B banks
//   Eight latch-based ICG instances per macroblock
//
// Dependencies:
//   icg_cell from actual_adder.v
//   precision_scalable_mac_pe_en
// ================================================================

module precision_packed_tile_4x4 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          clear_acc,
    input  wire          compute_en,

    input  wire [1:0]    precision_mode,
    input  wire          signed_a,
    input  wire          signed_b,

    input  wire [63:0]   a_in,
    input  wire          a_valid_in,
    output wire [63:0]   a_out,
    output wire          a_valid_out,

    input  wire [63:0]   b_in,
    input  wire          b_valid_in,
    output wire [63:0]   b_out,
    output wire          b_valid_out,

    output wire [575:0]  c_tile,
    output wire [3:0]    bank_capture_en
);

    localparam [1:0] MODE_INT4  = 2'b00;
    localparam [1:0] MODE_INT8  = 2'b01;
    localparam [1:0] MODE_INT16 = 2'b10;

    // ============================================================
    // 1. PRECISION DECODER
    // ============================================================

    wire [3:0] active_banks;

    assign active_banks =
        (precision_mode == MODE_INT4)  ? 4'b0001 :
        (precision_mode == MODE_INT8)  ? 4'b0011 :
        (precision_mode == MODE_INT16) ? 4'b1111 :
                                        4'b0000;

    // ============================================================
    // 2. REGISTER BANKS
    // ============================================================

    reg [15:0] a_bank0_q;
    reg [15:0] a_bank1_q;
    reg [15:0] a_bank2_q;
    reg [15:0] a_bank3_q;

    reg [15:0] b_bank0_q;
    reg [15:0] b_bank1_q;
    reg [15:0] b_bank2_q;
    reg [15:0] b_bank3_q;

    wire [63:0] a_bank_q;
    wire [63:0] b_bank_q;

    assign a_bank_q = {
        a_bank3_q,
        a_bank2_q,
        a_bank1_q,
        a_bank0_q
    };

    assign b_bank_q = {
        b_bank3_q,
        b_bank2_q,
        b_bank1_q,
        b_bank0_q
    };

    // ============================================================
    // 3. INDEPENDENT CLOCK-GATING ENABLES
    //
    // Each operand stream is controlled independently.
    //
    // A bank enabled only if:
    //   - its bank is active in the precision mode
    //   - a_valid_in is asserted
    //
    // B bank follows b_valid_in independently.
    // ============================================================

    wire [3:0] a_gate_en;
    wire [3:0] b_gate_en;

    assign a_gate_en = active_banks & {4{a_valid_in}};
    assign b_gate_en = active_banks & {4{b_valid_in}};

    // Existing debug output retained.
    // A bank is marked active if either stream captures.
    assign bank_capture_en = a_gate_en | b_gate_en;

    // ============================================================
    // 4. EIGHT LATCH-BASED CLOCK-GATING CELLS
    //
    // Reuse icg_cell from actual_adder.v.
    // Do not define icg_cell again here.
    // ============================================================

    wire [3:0] a_gclk;
    wire [3:0] b_gclk;

    genvar bank;

    generate
        for (bank = 0; bank < 4; bank = bank + 1) begin : GEN_BANK_ICG

            icg_cell u_icg_a (
                .clk  (clk),
                .en   (a_gate_en[bank]),
                .gclk (a_gclk[bank])
            );

            icg_cell u_icg_b (
                .clk  (clk),
                .en   (b_gate_en[bank]),
                .gclk (b_gclk[bank])
            );

        end
    endgenerate

    // ============================================================
    // 5. CLOCK-GATED A OPERAND REGISTERS
    // ============================================================

    always @(posedge a_gclk[0]) begin
        a_bank0_q <= a_in[15:0];
    end

    always @(posedge a_gclk[1]) begin
        a_bank1_q <= a_in[31:16];
    end

    always @(posedge a_gclk[2]) begin
        a_bank2_q <= a_in[47:32];
    end

    always @(posedge a_gclk[3]) begin
        a_bank3_q <= a_in[63:48];
    end

    // ============================================================
    // 6. CLOCK-GATED B OPERAND REGISTERS
    // ============================================================

    always @(posedge b_gclk[0]) begin
        b_bank0_q <= b_in[15:0];
    end

    always @(posedge b_gclk[1]) begin
        b_bank1_q <= b_in[31:16];
    end

    always @(posedge b_gclk[2]) begin
        b_bank2_q <= b_in[47:32];
    end

    always @(posedge b_gclk[3]) begin
        b_bank3_q <= b_in[63:48];
    end

    // ============================================================
    // 7. REGISTERED VALID FORWARDING
    //
    // The original valid pipeline remains on the system clock.
    // This is important because an invalid cycle must also
    // propagate through the array.
    // ============================================================

    reg a_valid_q;
    reg b_valid_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_valid_q <= 1'b0;
            b_valid_q <= 1'b0;
        end
        else if (clear_acc) begin
            a_valid_q <= 1'b0;
            b_valid_q <= 1'b0;
        end
        else begin
            a_valid_q <= a_valid_in;
            b_valid_q <= b_valid_in;
        end
    end

    assign a_out = a_bank_q;
    assign b_out = b_bank_q;

    assign a_valid_out = a_valid_q;
    assign b_valid_out = b_valid_q;

    // Both registered operands must be valid to MAC.
    wire mac_valid;

    assign mac_valid =
        compute_en && a_valid_q && b_valid_q;

    // ============================================================
    // 8. PRECISION-DEPENDENT LANE UNPACKING
    //
    // INT4:
    //   Four 4-bit operands in bank 0
    //
    // INT8:
    //   Four 8-bit operands in banks 0 and 1
    //
    // INT16:
    //   Four 16-bit operands in all four banks
    // ============================================================

    function [15:0] unpack_lane;

        input [63:0] packed_word;
        input [1:0]  mode;
        input integer lane;

        reg [3:0] nibble;
        reg [7:0] byte_value;

        begin

            unpack_lane = 16'b0;
            nibble = 4'b0;
            byte_value = 8'b0;

            case (mode)

                MODE_INT4: begin
                    nibble = packed_word[lane*4 +: 4];
                    unpack_lane = {12'b0, nibble};
                end

                MODE_INT8: begin
                    byte_value = packed_word[lane*8 +: 8];
                    unpack_lane = {8'b0, byte_value};
                end

                MODE_INT16: begin
                    unpack_lane = packed_word[lane*16 +: 16];
                end

                default: begin
                    unpack_lane = 16'b0;
                end

            endcase

        end
    endfunction

    // ============================================================
    // 9. SHARED OPERAND DISTRIBUTION
    //
    // A operand is shared across each local PE row.
    // B operand is shared across each local PE column.
    // ============================================================

    wire [15:0] a_lane_shared [0:3];
    wire [15:0] b_lane_shared [0:3];

    genvar lane;

    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : GEN_LANES

            assign a_lane_shared[lane] =
                unpack_lane(
                    a_bank_q,
                    precision_mode,
                    lane
                );

            assign b_lane_shared[lane] =
                unpack_lane(
                    b_bank_q,
                    precision_mode,
                    lane
                );

        end
    endgenerate

    // ============================================================
    // 10. SIXTEEN OUTPUT-STATIONARY MAC PEs
    //
    // The PEs already use the clock-gated actual_adder.
    // No changes are needed inside the PE module.
    // ============================================================

    genvar row;
    genvar col;

    generate

        for (row = 0; row < 4; row = row + 1) begin : GEN_PE_ROW

            for (col = 0; col < 4; col = col + 1) begin : GEN_PE_COL

                wire [31:0] product;
                wire        product_signed;
                wire [35:0] accumulator;

                precision_scalable_mac_pe_en u_mac (

                    .clk            (clk),
                    .rst_n          (rst_n),
                    .clr            (clear_acc),
                    .mac_en         (mac_valid),

                    .mode           (precision_mode),
                    .signed_x       (signed_a),
                    .signed_y       (signed_b),

                    .X              (a_lane_shared[row]),
                    .Y              (b_lane_shared[col]),

                    .product        (product),
                    .product_signed (product_signed),
                    .accumulator    (accumulator)

                );

                assign c_tile[
                    ((row*4 + col)*36) +: 36
                ] = accumulator;

            end
        end

    endgenerate

endmodule

`default_nettype wire
