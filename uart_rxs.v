module uart_rxs (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rxd,        // synchronized RX input
    input  wire       tick,       // 16x baud tick

    input  wire       par_en,     // parity enable
    input  wire       par_odd,    // 1 = odd, 0 = even

    output reg [7:0] rx_data,
    output reg       rx_valid,

    output reg       par_err,
    output reg       frm_err,
    output reg       brk
);

    // ------------------------------------------------
    // FSM states
    // ------------------------------------------------

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
    reg par_bit;


    // ------------------------------------------------
    // UART RX
    // ------------------------------------------------

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

                // ====================================
                // IDLE
                // ====================================

                IDLE: begin

                    if (!rxd) begin

                        t_cnt <= 4'd0;
                        state <= START;

                    end

                end


                // ====================================
                // START
                //
                // Wait 8 ticks = half bit
                // ====================================

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

                                // False start
                                state <= IDLE;

                            end

                        end
                        else begin

                            t_cnt <= t_cnt + 1'b1;

                        end

                    end

                end


                // ====================================
                // DATA
                //
                // Receive one bit every 16 ticks
                // ====================================

                DATA: begin

                    if (tick) begin

                        if (t_cnt == 4'd15) begin

                            t_cnt <= 4'd0;


                            // --------------------------------
                            // Update output bit-by-bit
                            //
                            // UART is LSB first:
                            //
                            // b_cnt = 0 -> rx_data[0]
                            // b_cnt = 1 -> rx_data[1]
                            // ...
                            // b_cnt = 7 -> rx_data[7]
                            // --------------------------------

                            rx_data[b_cnt] <= rxd;


                            // Also keep shift register
                            // for parity/break checking
                            shreg <= {rxd, shreg[7:1]};


                            if (b_cnt == 3'd7) begin

                                // All 8 data bits received

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


                // ====================================
                // PARITY
                // ====================================

                PARITY: begin

                    if (tick) begin

                        if (t_cnt == 4'd15) begin

                            t_cnt   <= 4'd0;
                            par_bit <= rxd;

                            state <= STOP;

                        end
                        else begin

                            t_cnt <= t_cnt + 1'b1;

                        end

                    end

                end


                // ====================================
                // STOP
                // ====================================

                STOP: begin

                    if (tick) begin

                        if (t_cnt == 4'd15) begin

                            t_cnt <= 4'd0;


                            // --------------------------------
                            // Complete byte received
                            // --------------------------------

                            rx_valid <= 1'b1;


                            // --------------------------------
                            // Parity error
                            // --------------------------------

                            if (par_en)
                                par_err <= (^shreg ^ par_odd ^ par_bit);
                            else
                                par_err <= 1'b0;


                            // --------------------------------
                            // Stop bit must be HIGH
                            // --------------------------------

                            frm_err <= ~rxd;


                            // --------------------------------
                            // Break detection
                            // --------------------------------

                            brk <= (~rxd &&
                                    (shreg == 8'h00) &&
                                    (!par_en || !par_bit));


                            // --------------------------------
                            // Next state
                            // --------------------------------

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


                // ====================================
                // WAIT
                // ====================================

                WAIT: begin

                    if (rxd)
                        state <= IDLE;

                end


                // ====================================
                // DEFAULT
                // ====================================

                default: begin

                    state <= IDLE;

                end

            endcase

        end

    end

endmodule
