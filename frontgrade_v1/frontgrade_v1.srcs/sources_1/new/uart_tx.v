//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/17/2026 02:12:28 PM
// Design Name: 
// Module Name: uart_rx
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

module uart_tx #(
    parameter CLK_FREQ = 200_000_000,
    parameter BAUD = 115200,
    localparam [30:0] INITIAL_SETUP = CLK_FREQ / BAUD, 
    localparam [3:0] TXU_BIT_ZERO    = 4'h0,
                     TXU_BIT_ONE     = 4'h1,
                     TXU_BIT_TWO     = 4'h2,
                     TXU_BIT_THREE   = 4'h3,
                     TXU_BIT_FOUR    = 4'h4,
                     TXU_BIT_FIVE    = 4'h5,
                     TXU_BIT_SIX     = 4'h6,
                     TXU_BIT_SEVEN   = 4'h7,
                     TXU_PARITY      = 4'h8,
                     TXU_STOP        = 4'h9,
                     TXU_SECOND_STOP = 4'ha,
                     //TXU_X       = 4'hb,
                     //TXU_X       = 4'hc,
                     TXU_BREAK       = 4'he,
                     TXU_IDLE        = 4'hf
                 
)(
    input wire i_clk, i_reset,
    input wire i_break, i_wr, 
    input wire [30:0] i_setup,
    input wire [7:0] i_data,
    input wire i_cts_n,//ready to send bit, 1 = use core without flow control
    output reg o_uart_tx,
    output wire o_busy
);

// Signal declarations 
wire [27:0] clocks_per_baud, break_condition;
wire [1:0] i_data_bits, data_bits;
wire use_parity, parity_odd, fixd_parity, i_parity_odd;
wire fixdp_value, dblstop, hw_flow_control;

// Registers
reg [30:0] r_setup;
reg	[27:0]	baud_counter;
reg	[3:0]	state;
reg	[7:0]	lcl_data;
reg	calc_parity, r_busy, zero_baud_counter, last_state;
reg	q_cts_n, qq_cts_n, ck_cts;

// Assignments
assign clocks_per_baud = {4'h0, r_setup[23:0]};
assign break_condition = {r_setup[23:0], 4'h0};
assign hw_flow_control = !r_setup[30];
assign i_data_bits     = i_setup[29:28];
assign dblstop         = r_setup[27];
assign use_parity      = r_setup[26];
assign fixd_parity     = r_setup[25];
assign i_parity_odd    = i_setup[24];
assign parity_odd      = r_setup[24];
assign fixdp_value     = r_setup[24];
 

// To avoid metastability on the initialization of the flow control
always @(posedge i_clk)
    if (i_reset)
        { qq_cts_n, q_cts_n} <= 2'b11;
    else 
        { qq_cts_n, q_cts_n} <= {q_cts_n, i_cts_n};
 
always @(posedge i_clk)
if(i_reset)
    ck_cts <= 1'b0;
else 
    ck_cts <= (!qq_cts_n)||(!hw_flow_control);
    
// States and busy     
initial	r_busy = 1'b1;
initial	state  = TXU_IDLE;
always @(posedge i_clk)
    // {{{
    if (i_reset) begin
        r_busy <= 1'b1;
        state <= TXU_IDLE;
    end else if (i_break) begin
        state <= TXU_BREAK;
        r_busy <= 1'b1;
    end else if (!zero_baud_counter) begin 
        r_busy <= 1'b1;
    end else if (state == TXU_BREAK) begin
        state <= TXU_IDLE;
        r_busy <= !ck_cts;
    end else if (state == TXU_IDLE) begin 
        if ((i_wr)&&(!r_busy)) begin
            r_busy <= 1'b1;
            case(i_data_bits)
                2'b00: state <= TXU_BIT_ZERO;
                2'b01: state <= TXU_BIT_ONE;
                2'b10: state <= TXU_BIT_TWO;
                2'b11: state <= TXU_BIT_THREE; //Here I may need to add the rest of the bits and increase i_data_bits
            endcase
        end else begin
            r_busy <= !ck_cts;
        end 
    end else begin // if not any of the other states, consider 1 clk tick in each 
        r_busy <= 1'b1;
        if (state[3] == 0) begin 
            if (state == TXU_BIT_SEVEN)
                state <= (use_parity)? TXU_PARITY:TXU_STOP;
            else 
                state <= state +1;
        end else if (state == TXU_PARITY) begin
            state <= TXU_STOP;
        end else if (state == TXU_STOP) begin
            if (dblstop)
                state <= TXU_SECOND_STOP;
            else 
                state <= TXU_IDLE;
        end else begin 
            state <= TXU_IDLE; // here we go back to idle to wait for the baud clock to finish counting
        end
    end
    // }}} 
                 
// copy of the busy reg
assign o_busy = (r_busy);
      
// setup reg: sts baud rate, stop bits, parity used and size of data word, continuosly set
initial r_setup = INITIAL_SETUP;
always @(posedge i_clk)
    if (!o_busy)
        r_setup <= i_setup;        
    
// actual data set and tranfer logic
initial lcl_data = 8'hff;
always @(posedge i_clk)
    if (!r_busy)
        lcl_data <= i_data;
    else if (zero_baud_counter)
        lcl_data <= { 1'b0, lcl_data[7:1]}; // on any baud0, shift the register to grab the next bit
        
// Logic 0:
//          break condition, start bit(idle, write and not busy), parity (it depends), 
initial o_uart_tx = 1'b1;
always @(posedge i_clk)
    if (i_reset)  
        o_uart_tx <= 1'b1;
     else if ((i_break)||((i_wr)&&(!r_busy))) 
        o_uart_tx <= 1'b0;
     else if (zero_baud_counter) 
        casez(state)
            4'b0???:    o_uart_tx <= lcl_data[0]; // this are dont care matches
            TXU_PARITY: o_uart_tx <= calc_parity;
            default:    o_uart_tx <= 1'b1;
        endcase

// Fixed or calculated parity bit 
initial calc_parity = 1 'b0;
always @(posedge i_clk)
    if(!o_busy)
        calc_parity <= i_setup[24];
    else if (fixd_parity)
        calc_parity <= fixdp_value;
    else if (zero_baud_counter) begin 
        if (state[3] == 0)
            calc_parity <= calc_parity ^ lcl_data[0];
        else if (state == TXU_IDLE)
            calc_parity <= parity_odd;
    end else if (!r_busy)
        calc_parity <= parity_odd;
           
// Baud conter drives all of the logic hereafter. complex logic  and ugly conditions
initial zero_baud_counter = 1'b0;
initial baud_counter = 28'h05;
always @(posedge i_clk)
    if (i_reset) begin
        baud_counter <= {INITIAL_SETUP[23:0], 4'h0 };
        zero_baud_counter <= 1'b0;
    end else if (i_break) begin
        baud_counter <= break_condition;
        zero_baud_counter <= 1'b0;
    end else begin 
        // {{{
        zero_baud_counter <= (baud_counter == 28'h01);
        if(!zero_baud_counter) // si es 0
            baud_counter <= baud_counter - 28'h01;
         // state break   
        else if (state == TXU_BREAK) begin 
            baud_counter <= 0;
            zero_baud_counter <= 1'b1;
        // state idle    
        end else if (state == TXU_IDLE) begin
            baud_counter <= 28'h0;
            zero_baud_counter <= 1'b1;
            if ((i_wr)&&(!r_busy)) begin
                baud_counter <= {4'h0, i_setup[23:0]} - 28'h01;
                zero_baud_counter <= 1'b0;
            end
        //last_state    
        end else if (last_state)
            baud_counter <= clocks_per_baud -28'h02;
        else 
            baud_counter <= clocks_per_baud -28'h01;
        // }}}
    end                     

// Regarding the last state
initial last_state = 1'b0;
always @(posedge i_clk)
    if (i_reset)
        last_state <= 1'b0;
    else if (dblstop)
        last_state <= (state == TXU_SECOND_STOP);
    else 
        last_state <= (state == TXU_STOP);
        
// This is for verilator so idk if it applies to this
wire unused;
assign unused = &{ 1'b0, i_parity_odd, data_bits};

//-------------------------------------------------------------------------------------
//Formal verification
`ifdef	FORMAL
// Declarations
// {{{
reg		fsv_parity;
reg	[30:0]	fsv_setup;
reg	[7:0]	fsv_data;
reg		f_past_valid;
// Our various sequence data declarations
reg	[5:0]	f_five_seq;
reg	[6:0]	f_six_seq;
reg	[7:0]	f_seven_seq;
reg	[8:0]	f_eight_seq;
reg	[2:0]	f_stop_seq;	// parity bit, stop bit, double stop bit
// }}}

// verification
initial	f_past_valid = 1'b0;
always @(posedge  i_clk)
    f_past_valid <= 1'b1;
    
// assignments of the logic
always @(posedge i_clk)
	if ((i_wr)&&(!o_busy))
		fsv_data <= i_data;

initial	fsv_setup = INITIAL_SETUP;
always @(posedge i_clk)
    if (!o_busy)
        fsv_setup <= i_setup;
        
// if this fails, it is treated as a failure, if true the assertion passes
always @(*)
    assert(r_setup == fsv_setup);
    
always @(posedge i_clk)
	assert(zero_baud_counter == (baud_counter == 0));
	
// siempre que este desocupado, zero_baud_counter =1
always @(*)
	if (!o_busy)
		assert(zero_baud_counter);
           
// a single baud interval
always @(posedge i_clk)
    if ((f_past_valid)&&(!$past(zero_baud_counter)) && (!$past(i_reset))&&(!$past(i_break))) begin
        assert($stable(o_uart_tx)); // $stable(signal) checks whether a signal has the same value as it had in the previous sampled clock cycle.
        assert($stable(state));
        assert($stable(lcl_data));
        if ((state != TXU_IDLE)&&(state != TXU_BREAK))
            assert($stable(calc_parity));
        assert(baud_counter == $past(baud_counter)-1'b1);
    end     

// VERY 4 
// one byte is sent = data, cks = clocks per bit
initial f_five_seq = 0;
always @(posedge i_clk)
    if ((i_reset)||(i_break))
        f_five_seq = 0;
    else if ((state == TXU_IDLE)&&(i_wr)&&(!o_busy) &&(i_data_bits == 2'b11)) // five data bits
        f_five_seq <= 1;
    else if (zero_baud_counter)
        f_five_seq <= f_five_seq << 1;
    
always @(*)
	if (|f_five_seq) begin // uses the reduction OR operator (|). It checks whether at least one bit of f_five_seq is 1.
		assert(fsv_setup[29:28] == data_bits);
		assert(data_bits == 2'b11);
		assert(baud_counter < fsv_setup[23:0]);
		assert(1'b0 == |f_six_seq);
		assert(1'b0 == |f_seven_seq);
		assert(1'b0 == |f_eight_seq);
		assert(r_busy);
		assert(state > 4'h2);
	end

always @(*)
	if (|f_five_seq) begin
		assert(fsv_setup[29:28] == data_bits);
		assert(data_bits == 2'b11);
		assert(baud_counter < fsv_setup[23:0]);
		assert(1'b0 == |f_six_seq);
		assert(1'b0 == |f_seven_seq);
		assert(1'b0 == |f_eight_seq);
		assert(r_busy);
		assert(state > 4'h2);
	end

////////////////////////////////////////////////////////////////////////
// VERY 5
always @(*)
    case(f_five_seq)
    6'h00: begin assert(1); end
    6'h01: begin
        assert(state == 4'h3);
        assert(o_uart_tx == 1'b0);
        assert(lcl_data[4:0] == fsv_data[4:0]);
        if (!fixd_parity)
            assert(calc_parity == parity_odd);
    end
    6'h02: begin
        assert(state == 4'h4);
        assert(o_uart_tx == fsv_data[0]);
        assert(lcl_data[3:0] == fsv_data[4:1]);
        if (!fixd_parity)
            assert(calc_parity == fsv_data[0] ^ parity_odd);
    end
    6'h04: begin
        assert(state == 4'h5);
        assert(o_uart_tx == fsv_data[1]);
        assert(lcl_data[2:0] == fsv_data[4:2]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[1:0]) ^ parity_odd);
    end
    6'h08: begin
        assert(state == 4'h6);
        assert(o_uart_tx == fsv_data[2]);
        assert(lcl_data[1:0] == fsv_data[4:3]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[2:0]) ^ parity_odd);
    end
    6'h10: begin
        assert(state == 4'h7);
        assert(o_uart_tx == fsv_data[3]);
        assert(lcl_data[0] == fsv_data[4]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[3:0]) ^ parity_odd);
    end
    6'h20: begin
        if (use_parity)
            assert(state == 4'h8);
        else
            assert(state == 4'h9);
        assert(o_uart_tx == fsv_data[4]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[4:0]) ^ parity_odd);
    end
    default: begin assert(0); end
    endcase
    
////////////////////////////////////////////////////////////////////////    
// VERY 6
initial	f_six_seq = 0;
always @(posedge i_clk)
    if ((i_reset)||(i_break))
        f_six_seq = 0;
    else if ((state == TXU_IDLE)&&(i_wr)&&(!o_busy)
            &&(i_data_bits == 2'b10)) // six data bits
        f_six_seq <= 1;
    else if (zero_baud_counter)
        f_six_seq <= f_six_seq << 1;

always @(*)
	if (|f_six_seq) begin
		assert(fsv_setup[29:28] == 2'b10);
		assert(fsv_setup[29:28] == data_bits);
		assert(baud_counter < fsv_setup[23:0]);

		assert(1'b0 == |f_five_seq);
		assert(1'b0 == |f_seven_seq);
		assert(1'b0 == |f_eight_seq);
		assert(r_busy);
		assert(state > 4'h1);
	end

always @(*)
case(f_six_seq)
    7'h00: begin assert(1); end
    7'h01: begin
        assert(state == 4'h2);
        assert(o_uart_tx == 1'b0);
        assert(lcl_data[5:0] == fsv_data[5:0]);
        if (!fixd_parity)
            assert(calc_parity == parity_odd);
    end
    7'h02: begin
        assert(state == 4'h3);
        assert(o_uart_tx == fsv_data[0]);
        assert(lcl_data[4:0] == fsv_data[5:1]);
        if (!fixd_parity)
            assert(calc_parity == fsv_data[0] ^ parity_odd);
    end
    7'h04: begin
        assert(state == 4'h4);
        assert(o_uart_tx == fsv_data[1]);
        assert(lcl_data[3:0] == fsv_data[5:2]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[1:0]) ^ parity_odd);
    end
    7'h08: begin
        assert(state == 4'h5);
        assert(o_uart_tx == fsv_data[2]);
        assert(lcl_data[2:0] == fsv_data[5:3]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[2:0]) ^ parity_odd);
    end
    7'h10: begin
        assert(state == 4'h6);
        assert(o_uart_tx == fsv_data[3]);
        assert(lcl_data[1:0] == fsv_data[5:4]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[3:0]) ^ parity_odd);
    end
    7'h20: begin
        assert(state == 4'h7);
        assert(lcl_data[0] == fsv_data[5]);
        assert(o_uart_tx == fsv_data[4]);
        if (!fixd_parity)
            assert(calc_parity == ((^fsv_data[4:0]) ^ parity_odd));
    end
    7'h40: begin
        if (use_parity)
            assert(state == 4'h8);
        else
            assert(state == 4'h9);
        assert(o_uart_tx == fsv_data[5]);
        if (!fixd_parity)
            assert(calc_parity == ((^fsv_data[5:0]) ^ parity_odd));
    end
    default: begin if (f_past_valid) assert(0); end
endcase

////////////////////////////////////////////////////////////////////////
// VERY 7
initial	f_seven_seq = 0;
always @(posedge i_clk)
    if ((i_reset)||(i_break))
        f_seven_seq = 0;
    else if ((state == TXU_IDLE)&&(i_wr)&&(!o_busy)
            &&(i_data_bits == 2'b01)) // seven data bits
        f_seven_seq <= 1;
    else if (zero_baud_counter)
        f_seven_seq <= f_seven_seq << 1;

always @(*)
if (|f_seven_seq) begin
    assert(fsv_setup[29:28] == 2'b01);
    assert(fsv_setup[29:28] == data_bits);
    assert(baud_counter < fsv_setup[23:0]);
    assert(1'b0 == |f_five_seq);
    assert(1'b0 == |f_six_seq);
    assert(1'b0 == |f_eight_seq);
    assert(r_busy);
    assert(state != 4'h0);
end

always @(*)
case(f_seven_seq)
    8'h00: begin assert(1); end
    8'h01: begin
        assert(state == 4'h1);
        assert(o_uart_tx == 1'b0);
        assert(lcl_data[6:0] == fsv_data[6:0]);
        if (!fixd_parity)
            assert(calc_parity == parity_odd);
    end
    8'h02: begin
        assert(state == 4'h2);
        assert(o_uart_tx == fsv_data[0]);
        assert(lcl_data[5:0] == fsv_data[6:1]);
        if (!fixd_parity)
            assert(calc_parity == fsv_data[0] ^ parity_odd);
    end
    8'h04: begin
        assert(state == 4'h3);
        assert(o_uart_tx == fsv_data[1]);
        assert(lcl_data[4:0] == fsv_data[6:2]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[1:0]) ^ parity_odd);
    end
    8'h08: begin
        assert(state == 4'h4);
        assert(o_uart_tx == fsv_data[2]);
        assert(lcl_data[3:0] == fsv_data[6:3]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[2:0]) ^ parity_odd);
    end
    8'h10: begin
        assert(state == 4'h5);
        assert(o_uart_tx == fsv_data[3]);
        assert(lcl_data[2:0] == fsv_data[6:4]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[3:0]) ^ parity_odd);
    end
    8'h20: begin
        assert(state == 4'h6);
        assert(o_uart_tx == fsv_data[4]);
        assert(lcl_data[1:0] == fsv_data[6:5]);
        if (!fixd_parity)
            assert(calc_parity == ((^fsv_data[4:0]) ^ parity_odd));
    end
    8'h40: begin
        assert(state == 4'h7);
        assert(lcl_data[0] == fsv_data[6]);
        assert(o_uart_tx == fsv_data[5]);
        if (!fixd_parity)
            assert(calc_parity == ((^fsv_data[5:0]) ^ parity_odd));
    end
    8'h80: begin
        if (use_parity)
            assert(state == 4'h8);
        else
            assert(state == 4'h9);
        assert(o_uart_tx == fsv_data[6]);
        if (!fixd_parity)
            assert(calc_parity == ((^fsv_data[6:0]) ^ parity_odd));
    end
    default: begin if (f_past_valid) assert(0); end
endcase

////////////////////////////////////////////////////////////////////////
// VERY 8
initial	f_eight_seq = 0;
always @(posedge i_clk)
    if ((i_reset)||(i_break))
        f_eight_seq = 0;
    else if ((state == TXU_IDLE)&&(i_wr)&&(!o_busy)
            &&(i_data_bits == 2'b00)) // Eight data bits
        f_eight_seq <= 1;
    else if (zero_baud_counter)
        f_eight_seq <= f_eight_seq << 1;

always @(*)
    if (|f_eight_seq) begin
        assert(fsv_setup[29:28] == 2'b00);
        assert(fsv_setup[29:28] == data_bits);
        assert(baud_counter < { 6'h0, fsv_setup[23:0]});
    
        assert(1'b0 == |f_five_seq);
        assert(1'b0 == |f_six_seq);
        assert(1'b0 == |f_seven_seq);
        assert(r_busy);
    end

always @(*)
case(f_eight_seq)
    9'h000: begin assert(1); end
    9'h001: begin
        assert(state == 4'h0);
        assert(o_uart_tx == 1'b0);
        assert(lcl_data[7:0] == fsv_data[7:0]);
        if (!fixd_parity)
            assert(calc_parity == parity_odd);
    end
    9'h002: begin
        assert(state == 4'h1);
        assert(o_uart_tx == fsv_data[0]);
        assert(lcl_data[6:0] == fsv_data[7:1]);
        if (!fixd_parity)
            assert(calc_parity == fsv_data[0] ^ parity_odd);
    end
    9'h004: begin
        assert(state == 4'h2);
        assert(o_uart_tx == fsv_data[1]);
        assert(lcl_data[5:0] == fsv_data[7:2]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[1:0]) ^ parity_odd);
    end
    9'h008: begin
        assert(state == 4'h3);
        assert(o_uart_tx == fsv_data[2]);
        assert(lcl_data[4:0] == fsv_data[7:3]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[2:0]) ^ parity_odd);
    end
    9'h010: begin
        assert(state == 4'h4);
        assert(o_uart_tx == fsv_data[3]);
        assert(lcl_data[3:0] == fsv_data[7:4]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[3:0]) ^ parity_odd);
    end
    9'h020: begin
        assert(state == 4'h5);
        assert(o_uart_tx == fsv_data[4]);
        assert(lcl_data[2:0] == fsv_data[7:5]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[4:0]) ^ parity_odd);
    end
    9'h040: begin
        assert(state == 4'h6);
        assert(o_uart_tx == fsv_data[5]);
        assert(lcl_data[1:0] == fsv_data[7:6]);
        if (!fixd_parity)
            assert(calc_parity == (^fsv_data[5:0]) ^ parity_odd);
    end
    9'h080: begin
        assert(state == 4'h7);
        assert(o_uart_tx == fsv_data[6]);
        assert(lcl_data[0] == fsv_data[7]);
        if (!fixd_parity)
            assert(calc_parity == ((^fsv_data[6:0]) ^ parity_odd));
    end
    9'h100: begin
        if (use_parity)
            assert(state == 4'h8);
        else
            assert(state == 4'h9);
        assert(o_uart_tx == fsv_data[7]);
        if (!fixd_parity)
            assert(calc_parity == ((^fsv_data[7:0]) ^ parity_odd));
    end
    default: begin if (f_past_valid) assert(0); end
endcase

// This is checking the baud counter after the bits
always @(posedge i_clk)
	if (((|f_five_seq[5:0]) || (|f_six_seq[6:0]) || (|f_seven_seq[7:0]) || (|f_eight_seq[8:0]))
		&& ($past(zero_baud_counter)))
		assert(baud_counter == { 4'h0, fsv_setup[23:0] }-1);
		
////////////////////////////////////////////////////////////////////////
// Stop sequence		
// This consists of any parity bit, as well as one or two stop bits
initial	f_stop_seq = 1'b0;
always @(posedge i_clk)
    if ((i_reset)||(i_break))
        f_stop_seq <= 0;
    else if (zero_baud_counter) begin
        f_stop_seq <= 0;
        //
        if (f_stop_seq[0]) begin// Coming from a parity bit
            if (dblstop)
                f_stop_seq[1] <= 1'b1;
            else
                f_stop_seq[2] <= 1'b1;
        end
        //
        if (f_stop_seq[1])
            f_stop_seq[2] <= 1'b1;
        //
        if (f_eight_seq[8] | f_seven_seq[7] | f_six_seq[6] | f_five_seq[5]) begin
            if (use_parity)
                f_stop_seq[0] <= 1'b1;
            else if (dblstop)
                f_stop_seq[1] <= 1'b1;
            else
                f_stop_seq[2] <= 1'b1;
        end
    end

always @(*)
    if (|f_stop_seq) begin
        assert(1'b0 == |f_five_seq[4:0]);
        assert(1'b0 == |f_six_seq[5:0]);
        assert(1'b0 == |f_seven_seq[6:0]);
        assert(1'b0 == |f_eight_seq[7:0]);
        assert(r_busy);
    end

always @(*)
    if (f_stop_seq[0]) begin
        // 9 if dblstop and use_parity
        if (dblstop)
            assert(state == TXU_STOP);
        else
            assert(state == TXU_STOP);
        assert(use_parity);
        assert(o_uart_tx == fsv_parity);
    end
    
always @(*)
    if (f_stop_seq[1]) begin
        // if (!use_parity)
        assert(state == TXU_SECOND_STOP);
        assert(dblstop);
        assert(o_uart_tx);
    end

always @(*)
    if (f_stop_seq[2]) begin
        assert(state == 4'hf);
        assert(o_uart_tx);
        assert(baud_counter < fsv_setup[23:0]-1'b1);
    end
    

always @(*)
    if (fsv_setup[25])
        fsv_parity <= fsv_setup[24];
    else
        case(fsv_setup[29:28])// indices must follow the declared range's direction
            2'b00: fsv_parity = (^fsv_data[7:0]) ^ fsv_setup[24];
            2'b01: fsv_parity = (^fsv_data[6:0]) ^ fsv_setup[24];
            2'b10: fsv_parity = (^fsv_data[5:0]) ^ fsv_setup[24];
            2'b11: fsv_parity = (^fsv_data[4:0]) ^ fsv_setup[24];
        endcase

//////////////////////////////////////////////////////////////////////
// Break sequence
reg	[1:0]	f_break_seq;

initial	f_break_seq = 2'b00;
always @(posedge i_clk)
    if (i_reset)
        f_break_seq <= 2'b00;
    else if (i_break)
        f_break_seq <= 2'b01;
    else if (!zero_baud_counter)
        f_break_seq <= { |f_break_seq, 1'b0 };
    else
        f_break_seq <= 0;

always @(posedge i_clk)
    if (f_break_seq[0])
        assert(baud_counter == { $past(fsv_setup[23:0]), 4'h0 });
always @(posedge i_clk)
    if ((f_past_valid)&&($past(f_break_seq[1]))&&(state != TXU_BREAK)) begin
        assert(state == TXU_IDLE);
        assert(o_uart_tx == 1'b1);
    end

always @(*)
    if (|f_break_seq) begin
        assert(state == TXU_BREAK);
        assert(r_busy);
        assert(o_uart_tx == 1'b0);
    end
    
//--------------------------------------------------------------------------------
`ifndef	TXUART
	reg	[28:0]		f_counter;
	initial	f_counter = 0;
	always @(posedge i_clk)
	if (!o_busy)
		f_counter <= 1'b0;
	else
		f_counter <= f_counter + 1'b1;

	always @(*)
	if (f_five_seq[0]|f_six_seq[0]|f_seven_seq[0]|f_eight_seq[0])
		// {{{
		assert(f_counter == (fsv_setup[23:0] - baud_counter - 1));
		// }}}
	else if (f_five_seq[1]|f_six_seq[1]|f_seven_seq[1]|f_eight_seq[1])
		// {{{
		assert(f_counter == ({4'h0, fsv_setup[23:0], 1'b0} - baud_counter - 1));
		// }}}
	else if (f_five_seq[2]|f_six_seq[2]|f_seven_seq[2]|f_eight_seq[2])
		// {{{
		assert(f_counter == ({4'h0, fsv_setup[23:0], 1'b0} + {5'h0, fsv_setup[23:0]} - baud_counter - 1));
		// }}}
	else if (f_five_seq[3]|f_six_seq[3]|f_seven_seq[3]|f_eight_seq[3])
		// {{{
		assert(f_counter == ({3'h0, fsv_setup[23:0], 2'b0} - baud_counter - 1));
		// }}}
	else if (f_five_seq[4]|f_six_seq[4]|f_seven_seq[4]|f_eight_seq[4])
		// {{{
		assert(f_counter == ({3'h0, fsv_setup[23:0], 2'b0} + {5'h0, fsv_setup[23:0]} - baud_counter - 1));
		// }}}
	else if (f_five_seq[5]|f_six_seq[5]|f_seven_seq[5]|f_eight_seq[5])
		// {{{
		assert(f_counter == ({3'h0, fsv_setup[23:0], 2'b0} + {4'h0, fsv_setup[23:0], 1'b0} - baud_counter - 1));
		// }}}
	else if (f_six_seq[6]|f_seven_seq[6]|f_eight_seq[6])
		// {{{
		assert(f_counter == ({3'h0, fsv_setup[23:0], 2'b0} + {5'h0, fsv_setup[23:0]} + {4'h0, fsv_setup[23:0], 1'b0} - baud_counter - 1));
		// }}}
	else if (f_seven_seq[7]|f_eight_seq[7])
		// {{{
		assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0} - baud_counter - 1));//8
		// }}}
	else if (f_eight_seq[8])
		// {{{
		assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0} +{5'h0, fsv_setup[23:0]} - baud_counter - 1));//9
		// }}}
	else if (f_stop_seq[0] || (!use_parity && f_stop_seq[1])) begin
		// {{{
		// Parity bit, or first of two stop bits
		case(data_bits)
		2'b00: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{4'h0, fsv_setup[23:0], 1'b0} // 10
				- baud_counter - 1));
		2'b01: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{5'h0, fsv_setup[23:0]} // 9
				- baud_counter - 1));
		2'b10: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				- baud_counter - 1)); // 8
		2'b11: assert(f_counter == ({3'h0, fsv_setup[23:0], 2'b0}
				+{5'h0, fsv_setup[23:0]}	// 7
				+{4'h0, fsv_setup[23:0], 1'b0}
				- baud_counter - 1));
		endcase
		// }}}
	end else if (!use_parity && !dblstop  && f_stop_seq[2])
	begin
		// {{{
		// No parity, single stop bit
		// Different from the one above, since the last counter is has
		// one fewer items within it
		case(data_bits)
		2'b00: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{4'h0, fsv_setup[23:0], 1'b0} // 10
				- baud_counter - 2));
		2'b01: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{5'h0, fsv_setup[23:0]} // 9
				- baud_counter - 2));
		2'b10: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				- baud_counter - 2)); // 8
		2'b11: assert(f_counter == ({3'h0, fsv_setup[23:0], 2'b0}
				+{5'h0, fsv_setup[23:0]}	// 7
				+{4'h0, fsv_setup[23:0], 1'b0}
				- baud_counter - 2));
		endcase
		// }}}
	end else if (f_stop_seq[1])
	begin
		// {{{
		// Parity and the first of two stop bits
		assert(dblstop && use_parity);
		case(data_bits)
		2'b00: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{5'h0, fsv_setup[23:0]}	// 11
				+{4'h0, fsv_setup[23:0], 1'b0}
				- baud_counter - 1));
		2'b01: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{4'h0, fsv_setup[23:0], 1'b0} // 10
				- baud_counter - 1));
		2'b10: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{5'h0, fsv_setup[23:0]}	// 9
				- baud_counter - 1));
		2'b11: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				- baud_counter - 1));		// 8
		endcase
		// }}}
	end else if ((dblstop ^ use_parity) && f_stop_seq[2])
	begin
		// {{{
		// Parity and one stop bit
		// assert(!dblstop && use_parity);
		case(data_bits)
		2'b00: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{5'h0, fsv_setup[23:0]}	// 11
				+{4'h0, fsv_setup[23:0], 1'b0}
				- baud_counter - 2));
		2'b01: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{4'h0, fsv_setup[23:0], 1'b0} // 10
				- baud_counter - 2));
		2'b10: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{5'h0, fsv_setup[23:0]}	// 9
				- baud_counter - 2));
		2'b11: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				- baud_counter - 2));		// 8
		endcase
		// }}}
	end else if (f_stop_seq[2])
	begin
		// {{{
		assert(dblstop);
		assert(use_parity);
		// Parity and two stop bits
		case(data_bits)
		2'b00: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{3'h0, fsv_setup[23:0], 2'b00}	// 12
				- baud_counter - 2));
		2'b01: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{5'h0, fsv_setup[23:0]}	// 11
				+{4'h0, fsv_setup[23:0], 1'b0}
				- baud_counter - 2));
		2'b10: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{4'h0, fsv_setup[23:0], 1'b0} // 10
				- baud_counter - 2));
		2'b11: assert(f_counter == ({2'h0, fsv_setup[23:0], 3'b0}
				+{5'h0, fsv_setup[23:0]}	// 9
				- baud_counter - 2));
		endcase
		// }}}
	end
`endif
//--------------------------------------------------------------------------------    
// Extra thingies
always @(*)
	assert((state < 4'hb)||(state >= 4'he));
// Careless/limiting assumption section
always @(*)
    assume(i_setup[23:0] > 2);
always @(*)
    assert(fsv_setup[23:0] > 2);  
    
`endif // FORMAL verification end


//-------------------------------------------------------------------------------------
 
endmodule