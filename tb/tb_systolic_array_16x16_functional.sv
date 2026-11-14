`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Vivado-friendly functional testbench for precision_packed_systolic_array.
//
// Runs all three precision modes (INT4/INT8/INT16) and all four A/B signedness
// combinations. For each transaction it:
//   1. Builds deterministic 16x16 input matrices.
//   2. Feeds four A row-groups and four B column-groups with the RTL tile skew.
//   3. Computes a software golden C=A*B in the testbench only.
//   4. Waits for done and compares all 256 36-bit outputs at the active width.
//
// Add the five RTL files under rtl/ as Design Sources and this file as the
// Simulation Top. The source RTL uses unpacked net arrays; in Vivado, set the
// RTL .v files' File Type to SystemVerilog (or use xvlog -sv).
// -----------------------------------------------------------------------------

module tb_systolic_array_16x16_functional;
    localparam integer PE_N   = 16;
    localparam integer GRID   = 4;
    localparam integer COUNT_W = 5;

    reg clk;
    reg rst_n;
    reg start;
    reg [1:0] precision_mode;
    reg signed_a;
    reg signed_b;

    reg [GRID*64-1:0] a_left_data;
    reg [GRID-1:0]    a_left_valid;
    reg [GRID*64-1:0] b_top_data;
    reg [GRID-1:0]    b_top_valid;

    wire busy;
    wire done;
    wire [1:0] active_mode;
    wire active_signed_a;
    wire active_signed_b;
    wire [COUNT_W-1:0] cycle_count;
    wire [1:0] state_debug;
    wire [PE_N*PE_N*36-1:0] c_flat;

    reg [15:0] matrix_a [0:15][0:15];
    reg [15:0] matrix_b [0:15][0:15];
    reg [63:0] golden   [0:255];

    integer feed_g;
    integer feed_lane;
    integer feed_k;

    integer mode_index;
    integer sign_index;
    integer row_index;
    integer col_index;
    integer k_index;
    integer data_width;
    integer acc_width;
    integer data_mask;
    integer a_value;
    integer b_value;
    integer base_index;
    integer error_count;
    integer total_transactions;
    integer total_outputs_checked;

    reg [63:0] acc_mask;
    reg [63:0] got_value;
    reg [63:0] expected_value;
    reg signed [63:0] sum_value;
    reg signed [63:0] decoded_a;
    reg signed [63:0] decoded_b;

    // 3.333 ns clock, matching the supplied timing constraint.
    always #1.6665 clk = ~clk;

    precision_packed_systolic_array #(
        .PE_N(PE_N)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .precision_mode(precision_mode),
        .signed_a(signed_a),
        .signed_b(signed_b),
        .a_left_data(a_left_data),
        .a_left_valid(a_left_valid),
        .b_top_data(b_top_data),
        .b_top_valid(b_top_valid),
        .busy(busy),
        .done(done),
        .active_mode(active_mode),
        .active_signed_a(active_signed_a),
        .active_signed_b(active_signed_b),
        .cycle_count(cycle_count),
        .state_debug(state_debug),
        .c_flat(c_flat)
    );

    // -------------------------------------------------------------------------
    // Boundary feeder.
    // A group g feeds global rows 4*g..4*g+3.
    // B group g feeds global columns 4*g..4*g+3.
    // Each boundary group is delayed by g cycles. The 4x4 macroblock mesh
    // adds one registered forwarding stage per macroblock crossed, giving the
    // same-operand pairing at tile (r,c) after the r+c schedule skew.
    // -------------------------------------------------------------------------
    always @* begin
        a_left_data  = {GRID*64{1'b0}};
        b_top_data   = {GRID*64{1'b0}};
        a_left_valid = {GRID{1'b0}};
        b_top_valid  = {GRID{1'b0}};

        for (feed_g = 0; feed_g < GRID; feed_g = feed_g + 1) begin
            feed_k = cycle_count;
            feed_k = feed_k - feed_g;

            if ((state_debug == 2'd2) && (feed_k >= 0) && (feed_k < PE_N)) begin
                a_left_valid[feed_g] = 1'b1;
                b_top_valid[feed_g]  = 1'b1;

                for (feed_lane = 0; feed_lane < 4; feed_lane = feed_lane + 1) begin
                    case (active_mode)
                        2'b00: begin // INT4: four 4-bit lane values in 16 bits.
                            a_left_data[feed_g*64 + feed_lane*4 +: 4] =
                                matrix_a[feed_g*4+feed_lane][feed_k][3:0];
                            b_top_data[feed_g*64 + feed_lane*4 +: 4] =
                                matrix_b[feed_k][feed_g*4+feed_lane][3:0];
                        end
                        2'b01: begin // INT8: four bytes across two active banks.
                            a_left_data[feed_g*64 + feed_lane*8 +: 8] =
                                matrix_a[feed_g*4+feed_lane][feed_k][7:0];
                            b_top_data[feed_g*64 + feed_lane*8 +: 8] =
                                matrix_b[feed_k][feed_g*4+feed_lane][7:0];
                        end
                        2'b10: begin // INT16: four 16-bit lane values.
                            a_left_data[feed_g*64 + feed_lane*16 +: 16] =
                                matrix_a[feed_g*4+feed_lane][feed_k][15:0];
                            b_top_data[feed_g*64 + feed_lane*16 +: 16] =
                                matrix_b[feed_k][feed_g*4+feed_lane][15:0];
                        end
                        default: begin
                            a_left_valid[feed_g] = 1'b0;
                            b_top_valid[feed_g]  = 1'b0;
                        end
                    endcase
                end
            end
        end
    end

    // Convert a raw two's-complement bit pattern into a signed 64-bit value.
    function signed [63:0] decode_operand;
        input [15:0] raw_value;
        input integer width_bits;
        input sign_enable;
        reg [63:0] temp_value;
        reg [63:0] width_mask;
        begin
            width_mask = (64'd1 << width_bits) - 1'b1;
            temp_value = {48'd0, raw_value} & width_mask;
            if (sign_enable && temp_value[width_bits-1])
                temp_value = temp_value - (64'd1 << width_bits);
            decode_operand = $signed(temp_value);
        end
    endfunction

    // Generate a deterministic, non-constant matrix pair for the selected mode
    // and signedness, then compute the reference matrix multiplication.
    task build_test_vectors;
        input integer selected_mode;
        input integer selected_sign;
        integer r;
        integer c;
        integer k;
        integer w;
        integer mask_value;
        reg signed [63:0] ax;
        reg signed [63:0] by;
        reg signed [63:0] accum;
        begin
            case (selected_mode)
                0: begin w = 4;  mask_value = 15;    end
                1: begin w = 8;  mask_value = 255;   end
                default: begin w = 16; mask_value = 65535; end
            endcase

            for (r = 0; r < PE_N; r = r + 1) begin
                for (k = 0; k < PE_N; k = k + 1) begin
                    a_value = (r*37 + k*19 + r*k*3 + selected_mode*11 + selected_sign*7 + 13) & mask_value;
                    b_value = (k*17 + r*29 + k*r*5 + selected_mode*7 + selected_sign*3 + 5) & mask_value;

                    // Include explicit boundary patterns as well as mixed values.
                    if ((r == 0) && (k == 0)) begin
                        a_value = mask_value;
                        b_value = mask_value;
                    end
                    else if ((r == 0) && (k == 1)) begin
                        a_value = (1 << (w-1));
                        b_value = (1 << (w-1)) - 1;
                    end
                    else if ((r == 1) && (k == 0)) begin
                        a_value = 0;
                        b_value = 1;
                    end

                    matrix_a[r][k] = a_value[15:0];
                    matrix_b[k][r] = b_value[15:0];
                end
            end

            for (r = 0; r < PE_N; r = r + 1) begin
                for (c = 0; c < PE_N; c = c + 1) begin
                    accum = 64'sd0;
                    for (k = 0; k < PE_N; k = k + 1) begin
                        ax = decode_operand(matrix_a[r][k], w, selected_sign[1]);
                        by = decode_operand(matrix_b[k][c], w, selected_sign[0]);
                        accum = accum + (ax * by);
                    end
                    golden[r*PE_N+c] = accum;
                end
            end
        end
    endtask

    // Run one full 16x16 matrix multiplication and compare all 256 results.
    task run_one_case;
        input integer selected_mode;
        input integer selected_sign;
        integer r;
        integer c;
        integer out_bits;
        reg [63:0] compare_mask;
        begin
            case (selected_mode)
                0: begin data_width = 4;  acc_width = 12; end
                1: begin data_width = 8;  acc_width = 20; end
                default: begin data_width = 16; acc_width = 36; end
            endcase
            data_mask = (1 << data_width) - 1;
            acc_mask = (64'd1 << acc_width) - 1'b1;
            compare_mask = acc_mask;

            build_test_vectors(selected_mode, selected_sign);

            // Wait until the previous transaction has returned to IDLE.
            while ((busy !== 1'b0) || (done !== 1'b0))
                @(negedge clk);

            @(negedge clk);
            precision_mode = selected_mode[1:0];
            signed_a = selected_sign[1];
            signed_b = selected_sign[0];
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            wait (done === 1'b1);
            #0.2;

            if (cycle_count !== 5'd22) begin
                $display("FAIL: expected terminal cycle_count=22, got %0d", cycle_count);
                $fatal(1);
            end
            if (active_mode !== selected_mode[1:0] ||
                active_signed_a !== selected_sign[1] ||
                active_signed_b !== selected_sign[0]) begin
                $display("FAIL: mode/signedness was not latched correctly");
                $fatal(1);
            end

            error_count = 0;
            for (r = 0; r < PE_N; r = r + 1) begin
                for (c = 0; c < PE_N; c = c + 1) begin
                    base_index = (r*PE_N + c)*36;
                    got_value = {28'd0, c_flat[base_index +: 36]} & compare_mask;
                    expected_value = golden[r*PE_N+c] & compare_mask;
                    if (got_value !== expected_value) begin
                        error_count = error_count + 1;
                        if (error_count <= 8)
                            $display("MISMATCH mode=%0d sign=%0d C[%0d][%0d] got=%h expected=%h",
                                     selected_mode, selected_sign, r, c,
                                     got_value, expected_value);
                    end
                end
            end

            if (error_count != 0) begin
                $display("FAIL: mode=%0d sign=%0d errors=%0d", selected_mode, selected_sign, error_count);
                $fatal(1);
            end

            total_transactions = total_transactions + 1;
            total_outputs_checked = total_outputs_checked + PE_N*PE_N;
            $display("PASS: mode=%0d sign=%0d width=%0d acc_width=%0d : 256/256 outputs correct; compute cycles=23",
                     selected_mode, selected_sign, data_width, acc_width);

            // In S_DONE, start=0 causes return to S_IDLE on the next clock.
            @(negedge clk);
            while (done !== 1'b0)
                @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        precision_mode = 2'b00;
        signed_a = 1'b0;
        signed_b = 1'b0;
        a_left_data = 0;
        a_left_valid = 0;
        b_top_data = 0;
        b_top_valid = 0;
        total_transactions = 0;
        total_outputs_checked = 0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // All three precision modes × all four signedness combinations:
        // 12 complete matrix transactions, 3,072 output checks.
        for (mode_index = 0; mode_index < 3; mode_index = mode_index + 1) begin
            for (sign_index = 0; sign_index < 4; sign_index = sign_index + 1) begin
                run_one_case(mode_index, sign_index);
            end
        end

        $display("============================================================");
        $display("FUNCTIONAL TEST PASS: transactions=%0d outputs_checked=%0d errors=0",
                 total_transactions, total_outputs_checked);
        $display("Modes: INT4, INT8, INT16 | signedness: U/U, U/S, S/U, S/S");
        $display("============================================================");
        $finish;
    end

    // Watchdog prevents a stalled controller from leaving the sim running forever.
    initial begin
        #200000;
        $display("FAIL: testbench watchdog timeout");
        $fatal(1);
    end
endmodule
