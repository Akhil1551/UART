module uart_rx (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rxd,        // synchronized RX input
    input  wire       tick,       // 16x baud tick

    input  wire       par_en,     // parity enable
    input  wire       par_odd,    // 1 = odd, 0 = even

    output reg [7:0]  rx_data,
    output reg        rx_valid,

    output reg        par_err,
    output reg        frm_err,
    output reg        brk
);

    localparam IDLE   = 3'd0;
    localparam START  = 3'd1;
    localparam DATA   = 3'd2;
    localparam PARITY = 3'd3;
    localparam STOP   = 3'd4;
    localparam WAIT   = 3'd5;

    reg [2:0] state;

    // Counts 0 to 15 inside one UART bit
    reg [3:0] t_cnt;

    // Counts received data bits 0 to 7
    reg [2:0] b_cnt;

    // Temporary received byte
    reg [7:0] shreg;

    // Received parity bit
    reg       par_bit;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            state    <= IDLE;
            t_cnt    <= 4'd0;
            b_cnt    <= 3'd0;
            shreg    <= 8'd0;
            par_bit  <= 1'b0;

            rx_data  <= 8'd0;
            rx_valid <= 1'b0;

            par_err  <= 1'b0;
            frm_err  <= 1'b0;
            brk      <= 1'b0;
        end

        else begin

            // rx_valid is a one-cycle pulse
            rx_valid <= 1'b0;


            case (state)

                IDLE: begin

                    if (!rxd) begin
                        t_cnt <= 4'd0;
                        state <= START;
                    end

                end


                // ------------------------------------
                // START
                // Wait 8 ticks = half bit
                // Then verify that RX is still LOW
                // ------------------------------------
                START: begin

                    if (tick) begin

                        if (t_cnt == 4'd7) begin

                            t_cnt <= 4'd0;

                            if (!rxd) begin
                                // Valid start bit
                                b_cnt <= 3'd0;
                                state <= DATA;
                            end
                            else begin
                                // False start / glitch
                                state <= IDLE;
                            end

                        end
                        else begin
                            t_cnt <= t_cnt + 1'b1;
                        end

                    end

                end


                DATA: begin

                    if (tick) begin

                        if (t_cnt == 4'd15) begin

                            t_cnt <= 4'd0;

                            // Shift received bit in
                            // LSB-first reception
                            shreg <= {rxd, shreg[7:1]};

                            if (b_cnt == 3'd7) begin

                                if (par_en)
                                    state <= PARITY;
                                else
                                    state <= STOP;
                            end
                            else begin
                                b_cnt <= b_cnt + 1'b1;
                            end

                        end
                        else begin
                            t_cnt <= t_cnt + 1'b1;
                        end

                    end

                end

                PARITY: begin

                    if (tick) begin

                        if (t_cnt == 4'd15) begin

                            t_cnt   <= 4'd0;
                            par_bit <= rxd;
                            state   <= STOP;

                        end
                        else begin
                            t_cnt <= t_cnt + 1'b1;
                        end

                    end

                end


                STOP: begin

                    if (tick) begin

                        if (t_cnt == 4'd15) begin

                            t_cnt <= 4'd0;

                            // Output received byte
                            rx_data  <= shreg;
                            rx_valid <= 1'b1;

                            // Parity error
                            if (par_en)
                                par_err <= (^shreg ^ par_odd ^ par_bit);
                            else
                                par_err <= 1'b0;

                            // Stop bit must be HIGH
                            frm_err <= ~rxd;

                            // Break:
                            // data = 00, parity low (if enabled),
                            // and stop bit low
                            brk <= (~rxd &&
                                    (shreg == 8'h00) &&
                                    (!par_en || !par_bit));

                            // If stop bit is HIGH,
                            // immediately wait for next frame.
                            //
                            // If LOW, remain in WAIT until
                            // the line returns HIGH.
                            if (rxd)
                                state <= IDLE;
                            else
                                state <= WAIT;

                        end
                        else begin
                            t_cnt <= t_cnt + 1'b1;
                        end

                    end

                end


                // ------------------------------------
                // WAIT
                // Used after framing error / break.
                // Wait until line becomes HIGH.
                // ------------------------------------
                WAIT: begin

                    if (rxd)
                        state <= IDLE;

                end


                default: begin
                    state <= IDLE;
                end

            endcase

        end

    end

endmodule
