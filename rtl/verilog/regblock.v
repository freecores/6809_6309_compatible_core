/*
 * MC6809 Register block, dual ported
 */
`include "defs.v"


module regblock(
	input wire clk_in,
	input wire [3:0] path_left_addr,
	input wire [3:0] path_right_addr,
	input wire [3:0] write_reg_addr,
	input wire [7:0] eapostbyte, // effective address post byte
	input wire [15:0] offset16, // up to 16 bit offset for effective address calculation
	input wire write_reg,
	input wire write_post,
	input wire write_pc,
	input wire inc_pc,
	input wire inc_su, /* increments S or U */
	input wire dec_su, /* decrements s or u */
	input wire use_s, /* increments S or U */
	input wire [15:0] data_w,
	input wire [15:0] new_pc,
	input wire [7:0] CCR_in,
	input wire write_flags,
	input wire set_e,
	input wire clear_e,
	output wire [7:0] CCR_o,
	output reg [15:0] path_left_data,
	output reg [15:0] path_right_data,
	output reg [15:0] eamem_addr,
	output wire [15:0] reg_pc,
	output wire [7:0] reg_dp,
	output wire [15:0] reg_su	
	);

`define ACCD { ACCA, ACCB }
reg [15:0] IX;
reg [15:0] IY;
reg [15:0] SU;
reg [15:0] SS;
reg [15:0] PC;

reg [7:0] ACCA;
reg [7:0] ACCB;	
reg [7:0] DP;
`define CCR { eflag, fflag, hflag, intff, nff, zff, vff, cff }

reg eflag, fflag, hflag;
reg intff, nff, zff, vff, cff;
reg [15:0] ea_reg, ea_reg_post;

assign CCR_o = `CCR;
assign reg_pc = PC;
assign reg_dp = DP;
assign reg_su = (use_s) ? SS:SU; /* stack pointer */
// left path output, always 16 bits
always @(*)
	begin
		case (path_left_addr)
			`RN_ACCA: 	path_left_data = { 8'h0, ACCA };
			`RN_ACCB: 	path_left_data = { 8'h0, ACCB };
			`RN_ACCD: 	path_left_data = `ACCD;
			`RN_IX: 	path_left_data = IX;
			`RN_IY: 	path_left_data = IY;
			`RN_U: 		path_left_data = SU;
			`RN_S: 		path_left_data = SS;
			`RN_PC: 	path_left_data = PC;
			`RN_DP: 	path_left_data = { 8'h0, DP };
			default:
				path_left_data = 16'hBEEF;
		endcase
	end
	
// right path output, always 16 bits
always @(*)
	begin
		case (path_right_addr)
			`RN_ACCA: path_right_data = { 8'h0, ACCA };
			`RN_ACCB: path_right_data = { 8'h0, ACCB };
			`RN_ACCD: path_right_data = `ACCD;
			`RN_IX: path_right_data = IX;
			`RN_IY: path_right_data = IY;
			`RN_U: path_right_data = SU;
			`RN_S: path_right_data = SS;
			`RN_DP: path_right_data = { 8'h0, DP };
			default:
				path_right_data = 16'hBEEF;
		endcase
	end

always @(*)
	begin
		case (eapostbyte[6:5])
			2'b00: ea_reg = IX;
			2'b01: ea_reg = IY;
			2'b10: ea_reg = SU;
			2'b11: ea_reg = SS;
		endcase
	end
// pre-decrement/postincrement
always @(*)
	begin
		ea_reg_post = ea_reg;
		casex (eapostbyte)
			8'b1xxx0000: ea_reg_post = ea_reg + 16'h1;
			8'b1xxx0001: ea_reg_post = ea_reg + 16'h2;
			8'b1xxx0010: ea_reg_post = ea_reg - 16'h1;
			8'b1xxx0011: ea_reg_post = ea_reg - 16'h2;
			//default: ea_reg_post = ea_reg;
		endcase
	end
	
/* EA calculation 
 * postbyte  bytes  assembler
 *
 * 0RRnnnnn    0     n,R  n is 5 bits signed
 * 1RRi0000    0     ,R+
 * 1RRi0001    0     ,R++
 * 1RRi0010    0     ,-R
 * 1RRi0011    0     ,--R
 * 1RR00100    0     ,R   no offset
 * 1RRi0101    0     B,R
 * 1RRi0110    0     A,R
 * 1RRi1000    1     n,R n is signed 8 bit
 * 1RRi1001    2     n,R n is signed 16 bit
 * 1RRi1011    0     D,R
 * 1xxi1100    1     n,PC  n is signed 8 bit postbyte
 * 1xxi1101    2     n,PC  n is 16 bit postbytes
 *
 * RR
 * 00  X
 * 01  Y
 * 10  U
 * 11  S
 */
always @(*)
	begin
		eamem_addr = 16'hFEED; // for debug purposes
		casex (eapostbyte)
			8'b0xx0xxxx: // 5 bit signed offset +
				eamem_addr = ea_reg + { 12'h0, eapostbyte[3:0] };
			8'b0xx1xxxx: // 5 bit signed offset -
				eamem_addr = ea_reg + { 12'hfff, eapostbyte[3:0] };
			8'b1xx_x_0000, // post increment, increment occurs at a later stage
			8'b1xx_x_0001, // post increment, increment occurs at a later stage
			8'b1xx_x_0100: // no offset
				eamem_addr = ea_reg;
			8'b1xx_x_0010, // pre decrement
			8'b1xx_x_0011: // pre decrement
				eamem_addr = ea_reg_post; // gets precalculated pre-decremented address
			8'b1xx_x_0101: // B,R
				eamem_addr = ea_reg + { {8{ACCB[7]}}, ACCB };
			8'b1xx_x_0110: // A,R
				eamem_addr = ea_reg + { {8{ACCA[7]}}, ACCA };
			8'b1xx_x_1011: // D,R
				eamem_addr = ea_reg + `ACCD;
			8'b1xx_x_1000: // n,R 8 bit offset
				eamem_addr = ea_reg + { offset16[7] ? 8'hff:8'h0, offset16[7:0] }; // from postbyte1
			8'b1xx_x_1001: // n,R // 16 bit offset
				eamem_addr = ea_reg + offset16;
			8'b1xx_x_1100: // n,PC
				eamem_addr = PC + { offset16[7] ? 8'hff:8'h0, offset16[7:0] };
			8'b1xx_x_1101: // n,PC
				eamem_addr = PC + offset16;
		endcase
	end

always @(posedge clk_in)
	begin
		if (write_reg)
			case (write_reg_addr)
				0: `ACCD <= data_w;
				1: IX <= data_w;
				2: IY <= data_w;
				3: SU <= data_w;
				4: SS <= data_w;
				5: PC <= data_w;
				8: ACCA <= data_w[7:0];
				9: ACCB <= data_w[7:0];
				10: `CCR <= data_w[7:0];
				11: DP <= data_w[7:0];
			endcase
		if (write_post) // write back predecrement/postincremented values
			begin
				case (eapostbyte[6:5])
					2'b00: IX <= ea_reg_post;
					2'b01: IY <= ea_reg_post;
					2'b10: SU <= ea_reg_post;
					2'b11: SS <= ea_reg_post;
				endcase
			end
		if (write_flags) 
			begin
				`CCR <= CCR_in;
			end
		if (set_e)
			eflag <= 1;
		if (clear_e)
			eflag <= 0;
		if (write_pc) PC <= new_pc;
		if (inc_pc) PC <= PC + 16'h1;
		if (inc_su) 
			if (use_s) SS <= SS + 16'h1;
			else SU <= SU + 16'h1;
		if (dec_su) 
			if (use_s) SS <= SS - 16'h1;
			else SU <= SU - 16'h1;
	end
		
`ifdef SIMULATION
initial
	begin
		PC = 16'hfffe;
		DP = 8'h00;
		IX = 16'h0;
		`CCR = 0;
		IY = 16'hA55A;
		SS = 16'h0f00;
		SU = 16'h0e00;
	end
`endif
endmodule
