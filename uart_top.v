module uart_top #(
    parameter integer CLK_FREQ   = 50_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer OVERSAMPLE = 16
)(
    input  wire       clk,
    input  wire       rst_n,

    // UART pins
    input  wire       rxd,
    output wire       txd,

    // TX interface
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    input  wire       par_en,
    input  wire       par_odd,
    output wire       tx_busy,

    // RX interface
    output wire [7:0] rx_data,
    output wire       rx_valid,
    output wire       par_err,
    output wire       frm_err,
    output wire       brk
);

    // ------------------------------------------------
    // Internal baud-rate tick signals
    // ------------------------------------------------

    wire tx_tick;
    wire rx_tick;


    // =================================================
    // 1. BAUD RATE GENERATOR
    // =================================================

    baudrate #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_baudrate (
        .clk     (clk),
        .rst_n   (rst_n),

        .tx_tick (tx_tick),
        .rx_tick (rx_tick)
    );


    // =================================================
    // 2. UART TRANSMITTER
    // =================================================

    uart_tx u_tx (
        .clk      (clk),
        .rst_n    (rst_n),

        .tx_data  (tx_data),
        .tx_start (tx_start),

        // One tick = one UART bit
        .tick     (tx_tick),

        .par_en   (par_en),
        .par_odd  (par_odd),

        .txd      (txd),
        .tx_busy  (tx_busy)
    );


    // =================================================
    // 3. UART RECEIVER
    // =================================================

    uart_rxs u_rx (
        .clk      (clk),
        .rst_n    (rst_n),

        // Direct RX connection for simulation
        .rxd      (rxd),

        // 16x oversampling tick
        .tick     (rx_tick),

        .par_en   (par_en),
        .par_odd  (par_odd),

        .rx_data  (rx_data),
        .rx_valid (rx_valid),

        .par_err  (par_err),
        .frm_err  (frm_err),
        .brk      (brk)
    );

endmodule
