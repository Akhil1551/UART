module baudrate #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter integer OVERSAMPLE = 16
)(
    input  wire clk,
    input  wire rst_n,

    output wire tx_tick,
    output wire rx_tick
);

    // Number of system-clock cycles per TX bit
    localparam integer TX_DIV = CLK_FREQ / BAUD_RATE;

    // Number of system-clock cycles per RX oversampling tick
    localparam integer RX_DIV = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);

    integer tx_count;
    integer rx_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_count <= 0;
            rx_count <= 0;
        end
        else begin

            // TX counter
            if (tx_count == TX_DIV - 1)
                tx_count <= 0;
            else
                tx_count <= tx_count + 1;
                
            if (rx_count == RX_DIV - 1)
                rx_count <= 0;
            else
                rx_count <= rx_count + 1;

        end
    end

    // One-cycle timing pulses
    assign tx_tick = (tx_count == TX_DIV - 1);
    assign rx_tick = (rx_count == RX_DIV - 1);

endmodule
