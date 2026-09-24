//////////////////////////////////////////////////////////////////////////////////
// Company: Radtest Ltd. 
// Engineer: Mariana MM
// 
// Create Date: 09/17/2026 02:18:23 PM
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices:  Genesys2
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision: 0.02 - Clock implementation 240926
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top (
input               clk     , // Top level system clock input.
input   wire [7:0]  sw    , // Slide switches.
input   wire        uart_rx_out, // UART Recieve pin. Out as in from the PC perspective
output  wire        uart_tx_in, // UART transmit pin. In as in from the PC perspective
output  wire [7:0]  led
);

assign led = sw;

// Clock frequency in hertz.
parameter CLK_HZ = 50000000; //50MHz
parameter BIT_RATE =   9600;
parameter PAYLOAD_BITS = 8;

wire [PAYLOAD_BITS-1:0]  uart_rx_data;
wire        uart_rx_valid;
wire        uart_rx_break;
wire        uart_tx_busy;
wire [PAYLOAD_BITS-1:0]  uart_tx_data;
wire        uart_tx_en;
reg  [PAYLOAD_BITS-1:0]  led_reg;

assign uart_tx_data = uart_rx_data; 
assign uart_tx_en   = uart_rx_valid;

reg  [PAYLOAD_BITS-1:0]  led_reg;


always @(posedge clk) begin
    if(|sw) begin
        led_reg <= 8'hAA;
    end else begin
        led_reg <= 8'h00;
    end
end

    /*end else if(uart_rx_valid) begin
        led_reg <= uart_rx_data[7:0];
    end*/

// ------------------------------------------------------------------------- 

//
// UART RX
uart_rx #(
.BIT_RATE(BIT_RATE),
.PAYLOAD_BITS(PAYLOAD_BITS),
.CLK_HZ  (CLK_HZ  )
) i_uart_rx(
.clk          (clk          ), // Top level system clock input.
.resetn       (sw[0]        ), // Asynchronous active low reset.
.uart_rx_out     (uart_rx_out     ), // UART Recieve pin.
.uart_rx_en   (1'b1         ), // Recieve enable
.uart_rx_break(), // Did we get a BREAK message?
.uart_rx_valid(uart_rx_valid), // Valid data recieved and available.
.uart_rx_data (uart_rx_data )  // The recieved data.
);


/* UART Transmitter module.

*/

uart_tx #(
.BIT_RATE(BIT_RATE),
.PAYLOAD_BITS(PAYLOAD_BITS),
.CLK_HZ  (CLK_HZ  )
) i_uart_tx(
.clk          (clk          ),
.resetn       (sw[0]        ),
.uart_tx_in     (uart_tx_in     ),
.uart_tx_en   (uart_tx_en   ),
.uart_tx_busy (uart_tx_busy ),
.uart_tx_data (uart_tx_data ) 
);
*/

endmodule