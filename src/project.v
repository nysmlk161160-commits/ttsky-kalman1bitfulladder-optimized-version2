// Top-level 11-bit add/sub sharing experiment.
// The divider and multiplier below are unchanged from the 1-bit baseline.
// Copyright (c) 2026. SPDX-License-Identifier: Apache-2.0

module full_adder_1bit (
    input wire a, b, cin,
    output wire sum, cout
);
    assign sum = a ^ b ^ cin;
    assign cout = (a & b) | ((a ^ b) & cin);
endmodule

module kalman_div1 (
    input wire clk, rst_n, start,
    input wire [9:0] p,
    input wire [10:0] s,
    output wire [6:0] result,
    output reg done
);
    reg [10:0] remainder;
    reg [11:0] trial_bits;
    reg [11:0] difference;
    reg [5:0] quotient;
    reg equal_case;
    assign result = {equal_case, quotient};
    reg [3:0] bit_index;
    reg [2:0] gain_index;
    reg carry;
    reg phase;
    reg running;
    wire denominator_bit = bit_index == 11 ? 1'b0 : s[bit_index];
    wire sum_bit, carry_next;
    wire [11:0] next_difference = {sum_bit, difference[11:1]};
    wire [5:0] next_quotient = {quotient[4:0], carry_next};

    full_adder_1bit divider_adder (
        .a(trial_bits[0]), .b(~denominator_bit), .cin(carry),
        .sum(sum_bit), .cout(carry_next)
    );
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            remainder <= 0;
            trial_bits <= 0;
            difference <= 0;
            quotient <= 0;
            bit_index <= 0;
            gain_index <= 0;
            carry <= 0;
            phase <= 0;
            running <= 0;
            equal_case <= 0;
            done <= 0;
        end else begin
            done <= 0;
            if (start) begin
                remainder <= {1'b0, p};
                quotient <= 0;
                equal_case <= (s != 0 && p == s);
                gain_index <= 0;
                phase <= 0;
                running <= (s != 0 && p != s);
                if (s == 0) begin
                    done <= 1;
                end else if (p == s) begin
                    done <= 1;
                end
            end else if (running) begin
                if (!phase) begin
                    trial_bits <= {remainder, 1'b0};
                    difference <= 0;
                    carry <= 1;
                    bit_index <= 0;
                    phase <= 1;
                end else begin
                    trial_bits <= trial_bits >> 1;
                    difference <= next_difference;
                    carry <= carry_next;
                    if (bit_index == 11) begin
                        remainder <= carry_next ? next_difference[10:0] : (remainder << 1);
                        quotient <= next_quotient;
                        if (gain_index == 5) begin
                            running <= 0;
                            done <= 1;
                        end else begin
                            gain_index <= gain_index + 1'b1;
                            phase <= 0;
                        end
                    end else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end
            end
        end
    end
endmodule

module kalman_mul1 (
    input wire clk, rst_n, start,
    input wire [6:0] a,
    input wire signed [10:0] b,
    output wire signed [10:0] result,
    output reg done
);
    reg [18:0] product;
    assign result = $signed(product[16:6]);
    reg [2:0] bit_count;
    reg [3:0] bit_index;
    reg carry;
    reg running;
    wire multiplicand_bit = bit_index == 11 ? b[10] : b[bit_index];
    wire sum_bit, carry_next;
    wire [18:0] shifted_product = {product[18], product[18:1]};
    full_adder_1bit multiplier_adder (
        .a(product[7]), .b(product[0] & multiplicand_bit), .cin(carry),
        .sum(sum_bit), .cout(carry_next)
    );
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product <= 0;
            bit_count <= 0;
            bit_index <= 0;
            carry <= 0;
            running <= 0;
            done <= 0;
        end else begin
            done <= 0;
            if (start) begin
                product <= {12'b0, a};
                bit_count <= 0;
                bit_index <= 0;
                carry <= 0;
                running <= 1;
            end else if (running) begin
                if (bit_index == 12) begin
                    product <= shifted_product;
                    bit_index <= 0;
                    carry <= 0;
                    if (bit_count == 6) begin
                        running <= 0;
                        done <= 1;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end else begin
                    product[18:7] <= {sum_bit, product[18:8]};
                    carry <= carry_next;
                    bit_index <= bit_index + 1'b1;
                end
            end
        end
    end
endmodule

module tt_um_example (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena, clk, rst_n
);
    reg [9:0] z, x, p, r;
    reg signed [10:0] delta;
    reg [10:0] s;
    reg [9:0] x_out, p_out;
    reg ready;
    reg [2:0] state;

    localparam IDLE=0, DIV_START=1, DIV_WAIT=2,
               X_START=3, X_WAIT=4, P_START=5,
               P_WAIT=6, FINISH=7;
    wire div_start = (state == DIV_START);
    wire mul_start = (state == X_START || state == P_START);
    wire [6:0] div_result;
    wire div_done, mul_done;
    wire signed [10:0] mul_result;
    wire signed [10:0] mul_b = (state == X_START || state == X_WAIT)
                                      ? delta : $signed({1'b0, p});

    // ONE shared 11-bit parallel add/sub datapath, time-multiplexed:
    // IDLE+start: P+R; DIV_START: Z-X; X_WAIT: X+K*(Z-X); P_WAIT: P-K*P.
    // delta is generated in DIV_START, overlapping the divider's START edge.
    wire alu_sub = (state == DIV_START || state == P_WAIT);
    wire [10:0] alu_a = (state == DIV_START) ? {z[9], z} :
                        (state == X_WAIT) ? {1'b0, x} : {1'b0, p};
    wire [10:0] alu_b_raw = (state == IDLE) ? {1'b0, r} :
                            (state == DIV_START) ? {x[9], x} :
                                                   {1'b0, mul_result[9:0]};
    wire [10:0] alu_b = alu_b_raw ^ {11{alu_sub}};
    wire [10:0] alu_y = alu_a + alu_b + alu_sub;

    wire [9:0] read_result = uio_in[5] ? p_out : x_out;
    assign uo_out = uio_in[2] ? {6'b0, read_result[9:8]} : read_result[7:0];
    assign uio_out = {ready, (state != IDLE), 6'b0};
    assign uio_oe = 8'b11000000;

    kalman_div1 divider (
        .clk(clk), .rst_n(rst_n), .start(div_start),
        .p(p), .s(s), .result(div_result), .done(div_done)
    );
    kalman_mul1 multiplier (
        .clk(clk), .rst_n(rst_n), .start(mul_start),
        .a(div_result), .b(mul_b), .result(mul_result), .done(mul_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            z <= 0;
            x <= 0;
            p <= 0;
            r <= 10'd320;
            delta <= 0;
            s <= 0;
            x_out <= 0;
            p_out <= 0;
            ready <= 0;
            state <= IDLE;
        end else begin
            if (state == IDLE && uio_in[3]) begin
                case (uio_in[1:0])
                    0: if (uio_in[2]) z[9:8] <= ui_in[1:0]; else z[7:0] <= ui_in;
                    1: if (uio_in[2]) x[9:8] <= ui_in[1:0]; else x[7:0] <= ui_in;
                    2: if (uio_in[2]) p[9:8] <= ui_in[1:0]; else p[7:0] <= ui_in;
                    3: if (uio_in[2]) r[9:8] <= ui_in[1:0]; else r[7:0] <= ui_in;
                endcase
            end
            case (state)
                IDLE: if (uio_in[4]) begin
                    s <= alu_y;
                    ready <= 0;
                    state <= DIV_START;
                end
                DIV_START: begin
                    delta <= $signed(alu_y);
                    state <= DIV_WAIT;
                end
                DIV_WAIT: if (div_done) begin
                    state <= X_START;
                end
                X_START: state <= X_WAIT;
                X_WAIT: if (mul_done) begin
                    x_out <= alu_y[9:0];
                    state <= P_START;
                end
                P_START: state <= P_WAIT;
                P_WAIT: if (mul_done) begin
                    p_out <= alu_y[9:0];
                    state <= FINISH;
                end
                FINISH: begin
                    ready <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
