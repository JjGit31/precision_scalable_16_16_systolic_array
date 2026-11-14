`timescale 1ns/1fs

// 16x16 precision-packed / temporal operand-sharing systolic-array VCD testbench.
// Matrix-generation cases are ported from the previously validated conventional
// 16x16 testbench supplied by the user.  Only the feeder/handshake is adapted to
// the current DUT interface and its 4x4 macro-grid timing.
module tb_array_vcd16;
    parameter integer PN = 16;
    localparam integer GRID = PN/4;
    localparam integer COUNT_W = $clog2(PN + 2*GRID - 1);
    localparam integer TESTS = 15;

    reg clk;
    reg rst_n;
    reg start;
    reg [1:0] precision_mode;
    reg signed_a;
    reg signed_b;

    reg [GRID*64-1:0] a_left_data;
    reg [GRID-1:0] a_left_valid;
    reg [GRID*64-1:0] b_top_data;
    reg [GRID-1:0] b_top_valid;

    wire busy;
    wire done;
    wire [1:0] active_mode;
    wire active_signed_a;
    wire active_signed_b;
    wire [COUNT_W-1:0] cycle_count;
    wire [1:0] state_debug;
    wire [PN*PN*36-1:0] c_flat;

    reg [15:0] A [0:PN-1][0:PN-1];
    reg [15:0] B [0:PN-1][0:PN-1];
    reg signed [63:0] golden [0:PN*PN-1];

    integer mode_arg;
    integer sign_arg;
    integer width_bits;
    integer span;
    integer lo;
    integer mask;
    integer acc_bits;
    integer test_num;
    integer passed;
    integer errors;

    reg [31:0] prng_state;
    reg [63:0] input_mask;
    reg [63:0] acc_mask;

    // Separate variables for the continuously-active boundary feeder.
    integer feed_g;
    integer feed_lane;
    integer feed_k;

    always #1.6665 clk = ~clk;  // 3.333 ns period, matching the PE timing target.

    precision_packed_systolic_array #(.PE_N(PN)) dut (
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

    // ------------------------------------------------------------------
    // CURRENT-DESIGN FEEDER
    //
    // Each 4x4 tile consumes one K-index per compute cycle.  Boundary group
    // g is delayed by g cycles.  A tile at (tr,tc) therefore receives A and B
    // for the same K-index after tr+tc forwarding stages.  Within a tile,
    // the four A lanes are shared across its four PE rows and the four B lanes
    // across its four PE columns, producing all 16 products concurrently.
    // ------------------------------------------------------------------
    always @* begin
        a_left_data  = {GRID*64{1'b0}};
        b_top_data   = {GRID*64{1'b0}};
        a_left_valid = {GRID{1'b0}};
        b_top_valid  = {GRID{1'b0}};

        for (feed_g = 0; feed_g < GRID; feed_g = feed_g + 1) begin
            feed_k = cycle_count;
            feed_k = feed_k - feed_g;

            if ((state_debug == 2'd2) && (feed_k >= 0) && (feed_k < PN)) begin
                a_left_valid[feed_g] = 1'b1;
                b_top_valid[feed_g]  = 1'b1;

                for (feed_lane = 0; feed_lane < 4; feed_lane = feed_lane + 1) begin
                    case (precision_mode)
                        2'b00: begin // INT4: four packed nibbles
                            a_left_data[feed_g*64 + feed_lane*4 +: 4] =
                                A[feed_g*4+feed_lane][feed_k][3:0];
                            b_top_data[feed_g*64 + feed_lane*4 +: 4] =
                                B[feed_k][feed_g*4+feed_lane][3:0];
                        end
                        2'b01: begin // INT8: four packed bytes
                            a_left_data[feed_g*64 + feed_lane*8 +: 8] =
                                A[feed_g*4+feed_lane][feed_k][7:0];
                            b_top_data[feed_g*64 + feed_lane*8 +: 8] =
                                B[feed_k][feed_g*4+feed_lane][7:0];
                        end
                        2'b10: begin // INT16: four packed 16-bit values
                            a_left_data[feed_g*64 + feed_lane*16 +: 16] =
                                A[feed_g*4+feed_lane][feed_k][15:0];
                            b_top_data[feed_g*64 + feed_lane*16 +: 16] =
                                B[feed_k][feed_g*4+feed_lane][15:0];
                        end
                        default: begin
                            // Reserved mode: leave operands and valids inactive.
                            a_left_valid[feed_g] = 1'b0;
                            b_top_valid[feed_g]  = 1'b0;
                        end
                    endcase
                end
            end
        end
    end

    function [31:0] scramble;
        input [31:0] v;
        reg [31:0] x;
        begin
            x = v ^ (v << 13);
            x = x ^ (x >> 17);
            scramble = x ^ (x << 5);
        end
    endfunction

    // Build exactly the 15 matrix cases from the supplied older testbench.
    // Case 0: deterministic mixed matrix with min/max/zero directed entries.
    // Case 1: all zero. Case 2: all maximum positive. Case 3: all minimum.
    // Cases 4..14: deterministic pseudo-random matrices using the same seed.
    task automatic make_matrices;
        input integer testcase;
        integer r;
        integer k;
        integer avalue;
        integer bvalue;
        integer c;
        integer idx;
        reg signed [63:0] ax;
        reg signed [63:0] by;
        reg signed [63:0] sum;
        begin
            for (r = 0; r < PN; r = r + 1) begin
                for (k = 0; k < PN; k = k + 1) begin
                    if (testcase == 0) begin
                        avalue = ((r*137 + k*73 + r*k*11 + 3) % span) + lo;
                        bvalue = ((k*109 + r*59 + k*r*7 + 5) % span) + lo;

                        if ((r == 0) && (k == 0)) begin
                            avalue = lo;
                            bvalue = lo;
                        end
                        if ((r == 0) && (k == 1)) begin
                            avalue = (span/2) - 1;
                            bvalue = (span/2) - 1;
                        end
                        if ((r == 0) && (k == 2)) begin
                            avalue = 0;
                            bvalue = 0;
                        end
                    end
                    else if (testcase == 1) begin
                        avalue = 0;
                        bvalue = 0;
                    end
                    else if (testcase == 2) begin
                        avalue = (span/2) - 1;
                        bvalue = (span/2) - 1;
                    end
                    else if (testcase == 3) begin
                        avalue = lo;
                        bvalue = lo;
                    end
                    else begin
                        prng_state = scramble(prng_state);
                        avalue = (prng_state & mask) + lo;
                        prng_state = scramble(prng_state);
                        bvalue = (prng_state & mask) + lo;
                    end

                    // Store raw two's-complement patterns, with no external sign extension.
                    A[r][k] = avalue & mask;
                    B[k][r] = bvalue & mask;
                end
            end

            // Golden C=A*B. Multiplication exists only in the testbench.
            for (r = 0; r < PN; r = r + 1) begin
                for (c = 0; c < PN; c = c + 1) begin
                    sum = 64'sd0;
                    for (k = 0; k < PN; k = k + 1) begin
                        ax = A[r][k] & input_mask;
                        by = B[k][c] & input_mask;

                        if (signed_a && ax[width_bits-1])
                            ax = ax - (64'sd1 << width_bits);
                        if (signed_b && by[width_bits-1])
                            by = by - (64'sd1 << width_bits);

                        sum = sum + (ax * by);
                    end
                    golden[r*PN+c] = sum;
                end
            end
        end
    endtask

    task automatic run_one_matrix;
        input integer testcase;
        integer r;
        integer c;
        integer base;
        reg [63:0] got_masked;
        reg [63:0] expected_masked;
        begin
            make_matrices(testcase);
            errors = 0;

            // A new transaction is accepted only when the controller is idle.
            @(negedge clk);
            if ((busy !== 1'b0) || (done !== 1'b0)) begin
                $display("FAIL: DUT not idle before matrix %0d", testcase+1);
                $fatal(1);
            end

            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            // The current controller ends at cycle_count=LAST_CYCLE (22 for 16x16).
            // The feeder above supplies K=0..15 with the required macro-row/column skew.
            wait (done === 1'b1);
            #1;

            for (r = 0; r < PN; r = r + 1) begin
                for (c = 0; c < PN; c = c + 1) begin
                    base = (r*PN + c)*36;
                    got_masked = c_flat[base +: 36] & acc_mask;
                    expected_masked = golden[r*PN+c] & acc_mask;

                    if (got_masked !== expected_masked) begin
                        errors = errors + 1;
                        if (errors <= 8)
                            $display("MISMATCH MODE=%0d SIGN=%0d MATRIX=%0d C[%0d][%0d] GOT=%h EXPECTED=%h",
                                     mode_arg, sign_arg, testcase+1, r, c,
                                     got_masked, expected_masked);
                    end
                end
            end

            if (errors != 0) begin
                $display("FAIL MODE=%0d SIGN=%0d MATRIX=%0d ERRORS=%0d",
                         mode_arg, sign_arg, testcase+1, errors);
                $fatal(1);
            end

            passed = passed + 1;
            $display("PASS MODE=%0d SIGN=%0d MATRIX=%0d/%0d: 256/256 CORRECT",
                     mode_arg, sign_arg, testcase+1, TESTS);

            // Let the controller leave S_DONE and return to S_IDLE before next start.
            @(negedge clk);
            while ((busy !== 1'b0) || (done !== 1'b0))
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
        errors = 0;
        passed = 0;
        prng_state = 32'd20261108;

        if (!$value$plusargs("m=%d", mode_arg)) mode_arg = 0;
        if (!$value$plusargs("s=%d", sign_arg)) sign_arg = 3;

        if ((mode_arg < 0) || (mode_arg > 2)) begin
            $display("FAIL: invalid mode=%0d (use 0=INT4, 1=INT8, 2=INT16)", mode_arg);
            $fatal(1);
        end
        if ((sign_arg < 0) || (sign_arg > 3)) begin
            $display("FAIL: invalid sign=%0d (use 0=U/U, 1=U/S, 2=S/U, 3=S/S)", sign_arg);
            $fatal(1);
        end

        case (mode_arg)
            0: begin width_bits = 4;  span = 16;    lo = -8;     acc_bits = 12; end
            1: begin width_bits = 8;  span = 256;   lo = -128;   acc_bits = 20; end
            2: begin width_bits = 16; span = 65536; lo = -32768; acc_bits = 36; end
            default: begin width_bits = 16; span = 65536; lo = -32768; acc_bits = 36; end
        endcase

        mask       = span - 1;
        input_mask = (64'd1 << width_bits) - 1;
        acc_mask   = (64'd1 << acc_bits) - 1;
        precision_mode = mode_arg[1:0];
        signed_a = sign_arg[1];
        signed_b = sign_arg[0];

        $display("============================================================");
        $display("START ARRAY16 VCD WORKLOAD: MODE=%0d SIGN=%0d WIDTH=%0d TESTS=%0d",
                 mode_arg, sign_arg, width_bits, TESTS);
        $display("Cases: directed mixed, zero, maximum, minimum, 11 deterministic random matrices");
        $display("PRNG seed: 20261108");
        $display("============================================================");

        // Match the existing package startup timing. The mode/signedness setup
        // edge and start pulse leave the first active operand-bank capture at ~65 ns,
        // simulation capture begins at time zero in xsim_vcd_capture.tcl.
        #22 rst_n = 1'b1;
        @(negedge clk);
        precision_mode = mode_arg[1:0];
        signed_a = sign_arg[1];
        signed_b = sign_arg[0];

        for (test_num = 0; test_num < TESTS; test_num = test_num + 1)
            run_one_matrix(test_num);

        if (passed != TESTS) begin
            $display("FAIL: incomplete suite, passed=%0d expected=%0d", passed, TESTS);
            $fatal(1);
        end

        $display("============================================================");
        $display("FINAL PASS: ARRAY16 mode=%0d sign=%0d matrices=%0d outputs=%0d errors=0",
                 mode_arg, sign_arg, passed, passed*PN*PN);
        $display("============================================================");
        // $stop returns control to the XSim batch Tcl script so it can close the VCD.
        $stop;
    end

    // 10 us watchdog; the 15-matrix workload is expected to finish well before it.
    initial begin
        #10000;
        $display("FAIL: ARRAY16 testbench timeout");
        $fatal(1);
    end
endmodule
