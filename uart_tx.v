module uart_tx (
    input  wire       clk,
    input  wire       rst_n,

    // Data interface
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    // Baud-rate timing
    // One tick = one UART bit period
    input  wire       tick,

    // Parity control
    input  wire       par_en,
    input  wire       par_odd,

    // UART serial output
    output reg        txd,

    // Indicates transmission is in progress
    output wire       tx_busy
);

    // ------------------------------------------------
    // FSM states
    // ------------------------------------------------

    localparam IDLE   = 3'd0;
    localparam START  = 3'd1;
    localparam DATA   = 3'd2;
    localparam PARITY = 3'd3;
    localparam STOP   = 3'd4;

    reg [2:0] state;

    // Holds the byte currently being transmitted
    reg [7:0] shreg;

    // Counts data bits: 0 to 7
    reg [2:0] b_cnt;

    // Generated parity bit
    reg parity_bit;


    // ------------------------------------------------
    // UART TX FSM
    // ------------------------------------------------

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state      <= IDLE;
            shreg      <= 8'h00;
            b_cnt      <= 3'd0;
            parity_bit <= 1'b0;

            // UART idle state is HIGH
            txd        <= 1'b1;

        end

        else begin

            case (state)

                // ====================================
                // IDLE
                // ====================================

                IDLE: begin

                    txd <= 1'b1;

                    if (tx_start) begin

                        // Capture data
                        shreg <= tx_data;

                        // Generate parity
                        //
                        // Even parity:
                        // parity_bit = XOR of data
                        //
                        // Odd parity:
                        // parity_bit = inverted XOR
                        //
                        parity_bit <= ^tx_data ^ par_odd;

                        // First data bit
                        b_cnt <= 3'd0;

                        // Start transmission
                        state <= START;

                    end

                end


                // ====================================
                // START BIT
                // ====================================

                START: begin

                    // Start bit = 0
                    txd <= 1'b0;

                    if (tick) begin

                        // Start bit completed
                        b_cnt <= 3'd0;

                        state <= DATA;

                    end

                end


                // ====================================
                // DATA BITS
                // ====================================

                DATA: begin

                    // Send LSB first
                    txd <= shreg[0];

                    if (tick) begin

                        // Shift to next data bit
                        shreg <= shreg >> 1;

                        if (b_cnt == 3'd7) begin

                            // All 8 data bits transmitted

                            if (par_en)
                                state <= PARITY;
                            else
                                state <= STOP;

                        end

                        else begin

                            b_cnt <= b_cnt + 1'b1;

                        end

                    end

                end


                // ====================================
                // PARITY BIT
                // ====================================

                PARITY: begin

                    txd <= parity_bit;

                    if (tick) begin

                        state <= STOP;

                    end

                end


                // ====================================
                // STOP BIT
                // ====================================

                STOP: begin

                    // Stop bit = 1
                    txd <= 1'b1;

                    if (tick) begin

                        // Transmission finished
                        state <= IDLE;

                    end

                end


                // ====================================
                // DEFAULT
                // ====================================

                default: begin

                    state <= IDLE;
                    txd   <= 1'b1;
                    b_cnt <= 3'd0;

                end

            endcase

        end

    end


    // ------------------------------------------------
    // TX busy
    // ------------------------------------------------

    assign tx_busy = (state != IDLE);

endmodule
