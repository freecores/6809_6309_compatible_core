
/*
 * Signals which registers have to be read/written for the current opcode
 *
 *
 *
 */
`include "defs.v"
module decode_regs(
	input wire cpu_clk,
	input wire [7:0] opcode,
	input wire [7:0] postbyte0,
	input wire page2_valid, // is 1 when the postbyte0 is a valid opcode (after it was loaded)
	input wire page3_valid, // is 1 when the postbyte0 is a valid opcode (after it was loaded)
	output wire [3:0] path_left_addr_o,
	output wire [3:0] path_right_addr_o,
	output wire [3:0] dest_reg_o,
	output reg [3:0] path_left_addr_lo,
	output reg [3:0] path_right_addr_lo,
	output reg [3:0] dest_reg_lo,
	output wire write_dest,
	output wire source_size,
	output wire result_size
	);
reg [3:0] path_left_addr, path_right_addr, dest_reg;
// for registers, memory writes are handled differently
assign write_dest = (dest_reg != `RN_INV);
assign source_size = (path_left_addr < `RN_ACCA);
// result size is used to determine the size of the argument
// to load, compare has no result, thus the source is used instead,
// why do we need the result size ?... because of tfr&exg 
assign result_size = (dest_reg == `RN_INV) ? (path_left_addr < `RN_ACCA):
                     (dest_reg < `RN_IMM16) ? 1:0;

assign path_right_addr_o = path_right_addr;
assign path_left_addr_o = path_left_addr;
assign dest_reg_o = dest_reg;


always @(opcode, postbyte0, page2_valid, page3_valid)
	begin
		path_left_addr = `RN_INV;
		path_right_addr = `RN_INV;
		dest_reg = `RN_INV;
		if (page2_valid)
			begin
				casex(postbyte0)
					8'h83, 8'h93, 8'ha3, 8'hb3: path_left_addr = `RN_ACCD; // cmpd
					8'h8c, 8'h9c, 8'hac, 8'hbc: path_left_addr = `RN_IY; // cmpy
					8'h8e, 8'h9e, 8'hae, 8'hbe: path_left_addr = `RN_IY; // ldy
					8'h8f, 8'h9f, 8'haf, 8'hbf: path_left_addr = `RN_IY; // sty
					8'hdf, 8'hef, 8'hff: path_left_addr = `RN_S; // STS
				endcase
				casex (postbyte0) // right arm
					8'h83, 8'h8c, 8'h8e, 8'hce: path_right_addr = `RN_IMM16;
					8'h93, 8'ha3, 8'hb3: path_right_addr = `RN_MEM16;
					8'h9c, 8'hac, 8'hbc: path_right_addr = `RN_MEM16;
					8'h9e, 8'hae, 8'hbe: path_right_addr = `RN_MEM16;
					8'h9f, 8'haf, 8'hbf: path_right_addr = `RN_MEM16; // STY
					8'hde, 8'hee, 8'hfe: path_right_addr = `RN_MEM16; // lds
				endcase
				casex(postbyte0) // dest
					8'h83, 8'h93, 8'ha3, 8'hb3: begin end // cmpd
					8'h8c, 8'h9c, 8'hac, 8'hbc: begin end // cmpy
					8'h8e, 8'h9e, 8'hae, 8'hbe: dest_reg = `RN_IY; // LDY
					8'hce, 8'hde, 8'hee, 8'hfe: dest_reg = `RN_S; // LDS
					8'h9f, 8'haf, 8'hbf: dest_reg = `RN_MEM16; // STY
					8'hdf, 8'hef, 8'hff: dest_reg = `RN_MEM16; // STS
				endcase
			end
		if (page3_valid)
			begin
				casex(postbyte0)
					8'h83, 8'h93, 8'ha3, 8'hb3: path_left_addr = `RN_U; // CMPU
					8'h8c, 8'h9c, 8'hac, 8'hbc: path_left_addr = `RN_S; // CMPS
				endcase
				casex (postbyte0) // right arm
					8'h83, 8'h8c: path_right_addr = `RN_IMM16; // CMPU, CMPS
					8'h93, 8'ha3, 8'hb3: path_right_addr = `RN_MEM16; // CMPU
					8'h9c, 8'hac, 8'hbc: path_right_addr = `RN_MEM16; // CMPS
				endcase
				casex(postbyte0) // dest
					8'h83, 8'h93, 8'ha3, 8'hb3: begin end // cmpu
					8'h8c, 8'h9c, 8'hac, 8'hbc: begin end // cmps
				endcase
			end
		// destination
		casex(opcode)
			8'h1a, 8'h1c: begin path_left_addr = `RN_CC; path_right_addr = `RN_IMM8; dest_reg = `RN_CC; end // ANDCC, ORCC
			8'h19: begin path_left_addr = `RN_ACCA; dest_reg = `RN_ACCA; end // DAA
			8'h1d: begin path_left_addr = `RN_ACCB; dest_reg = `RN_ACCA; end // SEX
			8'h1e, 8'h1f: begin dest_reg = postbyte0[3:0]; path_left_addr = postbyte0[7:4]; path_right_addr = postbyte0[3:0]; end // tfr, exg
			8'h30: dest_reg = `RN_IX;
			8'h31: dest_reg = `RN_IY;
			8'h32: dest_reg = `RN_S;
			8'h33: dest_reg = `RN_U;
			8'h39: dest_reg = `RN_PC; // rts
			8'h3d: begin path_left_addr = `RN_ACCA; path_right_addr = `RN_ACCB; dest_reg = `RN_ACCD; end // mul
			8'h4x: begin path_left_addr = `RN_ACCA; dest_reg = `RN_ACCA; end
			8'h5x: begin path_left_addr = `RN_ACCB; dest_reg = `RN_ACCB; end
			8'h0x, 8'h6x, 8'h7x:
				case (opcode[3:0]) 	
					4'he: begin end // no source or dest for jmp
					4'hf: begin dest_reg = `RN_MEM8; end // CLR, only dest
					default: begin path_left_addr = `RN_MEM8; dest_reg = `RN_MEM8; end
				endcase
			8'h8x, 8'h9x, 8'hax, 8'hbx: 
				case (opcode[3:0]) // default A->A
					4'h1, 4'h5: path_left_addr = `RN_ACCA; // CMP, BIT
					4'h3: begin path_left_addr = `RN_ACCD; dest_reg = `RN_ACCD; end
					4'h7: begin path_left_addr = `RN_ACCA; dest_reg = `RN_MEM8; end // sta
					4'hc: path_left_addr = `RN_IX; // cmpx
					4'hd: begin end // nothing active, jsr
					4'he: begin path_left_addr = `RN_IX; dest_reg = `RN_IX; end // ldx
					4'hf: begin path_left_addr = `RN_IX; dest_reg = `RN_MEM16; end // stx
					default: begin path_left_addr = `RN_ACCA; dest_reg = `RN_ACCA; end
				endcase
			8'hcx, 8'hdx, 8'hex, 8'hfx:
				case (opcode[3:0]) 
					4'h1, 4'h5: path_left_addr = `RN_ACCB; // CMP, BIT
					4'h3, 4'hc: begin path_left_addr = `RN_ACCD; dest_reg = `RN_ACCD; end
					4'h7: begin path_left_addr = `RN_ACCB; dest_reg = `RN_MEM8; end // store to mem
					4'hd: begin path_left_addr = `RN_ACCD; end // LDD
					4'he: begin path_left_addr = `RN_U; dest_reg = `RN_U; end // LDU
					4'hf: begin path_left_addr = `RN_U; dest_reg = `RN_MEM16; end // STU
					default: begin path_left_addr = `RN_ACCB; dest_reg = `RN_ACCB; end
				endcase
		endcase
		casex (opcode) // right arm
			// 8x and Cx
			8'b1x00_000x, 8'b1x00_0010: path_right_addr = `RN_IMM8; // sub, cmp, scb
			8'b1x00_0011, 8'b1x00_11x0: path_right_addr = `RN_IMM16; // cmpd, cmpx, ldx
			8'b1x00_010x, 8'b1x00_0110,	8'b1x00_10xx: path_right_addr = `RN_IMM8;
			// 9, A, B, D, E, F
			8'b1x01_000x, 8'b1x01_0010: path_right_addr = `RN_MEM8;
			8'b1x01_0011, 8'b1x01_11x0: path_right_addr = `RN_MEM16; // cmpd, cmpx, ldx
			8'b1x01_010x, 8'b1x01_0110,	8'b1x01_10xx: path_right_addr = `RN_MEM8;
			8'b1x1x_000x, 8'b1x1x_0010: path_right_addr = `RN_MEM8;
			8'b1x1x_0011, 8'b1x1x_11x0: path_right_addr = `RN_MEM16;
			8'b1x1x_010x, 8'b1x1x_0110,	8'b1x1x_10xx: path_right_addr = `RN_MEM8;
		endcase
	end
// latched versions are used to fetch regsiters
// not-latched version in the decoder
always @(posedge cpu_clk)
	begin
		path_right_addr_lo <= path_right_addr;
		path_left_addr_lo <= path_left_addr;
		dest_reg_lo <= dest_reg;
	end

endmodule

/* Decodes module and addressing mode for page 1 opcodes */
module decode_op(
	input wire [7:0] opcode,
	input wire [7:0] postbyte0,
	input wire page2_valid, // is 1 when the postbyte0 is a valid opcode (after it was loaded)
	input wire page3_valid, // is 1 when the postbyte0 is a valid opcode (after it was loaded)
	output reg [2:0] mode,
	output reg [2:0] optype,
	output reg use_s
	);
	
wire [3:0] oplo;
reg size;
assign oplo = opcode[3:0];

always @(opcode, postbyte0, page2_valid, page3_valid, oplo)
	begin
		//dsize = `DSZ_8; // data operand size
		//msize = `MSZ_8; // memory operand size
		optype = `OP_NONE;
		use_s = 1;
		mode = `NONE;
		size = 0;
		// Addressing mode
		casex(opcode)
			8'h0x: begin mode = `DIRECT; end
			//8'h0e: begin optype = `OP_JMP; end
			8'h12, 8'h13, 8'h19: mode = `INHERENT;
			8'h14, 8'h15, 8'h18, 8'h1b: mode = `NONE; // undefined opcodes
			8'h16: mode = `REL16;
			8'h17: begin mode = `REL16; optype = `OP_JSR; end
			8'h1a, 8'h1c, 8'h1d, 8'h1e, 8'h1f: mode = `IMMEDIATE; // handled in ALU ORCC, ANDCC, SEX
			
			8'h2x: mode = `REL8;
			8'h30, 8'h31, 8'h32, 8'h33: begin mode = `INDEXED;  optype = `OP_LEA; end
			8'h34: begin optype = `OP_PUSH; mode = `NONE; end
			8'h35: begin optype = `OP_PULL; mode = `NONE; end
			8'h36: begin optype = `OP_PUSH; mode = `NONE; use_s = 0; end
			8'h37: begin optype = `OP_PULL; mode = `NONE; use_s = 0; end
			8'h38, 8'h3e: mode = `NONE;
			// don't change to inh because SEQ_MEM_READ_x would not use register S as address
			8'h39, 8'h3b: begin  mode = `NONE; optype = `OP_RTS; end 
			8'h3a, 8'h3c, 8'h3d, 8'h3f: mode = `INHERENT;
			
			8'h4x: begin mode = `INHERENT; end
			8'h5x: begin mode = `INHERENT; end
			8'h6x: begin mode = `INDEXED; end
			//8'h6e: begin optype = `OP_JMP; end
			8'h7x: begin mode = `EXTENDED; end
			//8'h7e: begin optype = `OP_JMP; end
			8'h8x: 
				begin
					case (oplo)
						4'h3, 4'hc, 4'he: begin mode = `IMMEDIATE; size = 1; end
						4'hd: mode = `REL8; // bsr
						default: mode = `IMMEDIATE;
					endcase
				end
			8'hcx: 
				begin
					case (oplo)
						4'h3, 4'hc, 4'he: begin mode = `IMMEDIATE; size = 1; end
						default: mode = `IMMEDIATE;
					endcase
				end
			8'h9x, 8'hdx: begin mode = `DIRECT; end
			8'hax, 8'hex: begin mode = `INDEXED; end
			8'hbx, 8'hfx: begin mode = `EXTENDED; end
		endcase
		// Opcode type
		casex(opcode)
			8'b1xxx0110: optype = `OP_LD;
			8'h0e, 8'h6e, 8'h7e: optype = `OP_JMP;
			8'b11xx1100: optype = `OP_LD; // LDD
			8'b10xx1101: begin optype = `OP_JSR; end// bsr & jsr
			8'b1xxx1110: optype = `OP_LD; // LDX, LDU
			//8'b1xxx1111, 8'b11xx1101: optype = `OP_ST;
		endcase
		if (page2_valid == 1'b1)
			begin
				casex(postbyte0)
					8'h2x: mode = `REL16;
					8'h3f: mode = `INHERENT;
					8'h83: begin  mode = `IMMEDIATE; size = 1; end
					//8'h93, 8'ha3, 8'hb3: begin mem16 = 1; size = 1; end
					8'h8c: begin  mode = `IMMEDIATE; size = 1; end
					//8'h9c, 8'hac, 8'hbc: begin mem16 = 1; size = 1; end
					8'h8e: begin mode = `IMMEDIATE; size = 1; end
					//8'h9e, 8'hae, 8'hbe: begin mem16 = 1; size = 1; end
					//8'h9f, 8'haf, 8'hbf: begin  mem16 = 1; size = 1; end
					8'hce: begin  mode = `IMMEDIATE; size = 1; end
					//8'hde, 8'hee, 8'hfe: begin mem16 = 1; size = 1; end
					//8'hdf, 8'hef, 8'hff: begin mem16 = 1; size = 1; end
				endcase
				casex( postbyte0)
					8'h9x, 8'hdx: mode = `DIRECT;
					8'hax, 8'hex: mode = `INDEXED;
					8'hbx, 8'hfx: mode = `EXTENDED;
				endcase
				casex( postbyte0)
					8'b1xxx1110: optype = `OP_LD; // LDY, LDS
					//8'b1xxx1111, 8'b1xxx1101: optype = `OP_ST; // STY, STS
				endcase
			end
		if (page3_valid == 1'b1)
			begin
				casex(postbyte0)
					8'h3f: mode = `INHERENT;
					8'h83: begin mode = `IMMEDIATE; size = 1; end // CMPD
					//8'h93, 8'ha3, 8'hb3: begin mem16 = 1; size = 1; end // CMPD
					8'h8c: begin mode = `IMMEDIATE; size = 1; end
					//8'h9c, 8'hac, 8'hbc: begin mem16 = 1; size = 1; end
					8'h8e: begin mode = `IMMEDIATE; size = 1; end
					//8'h9e, 8'hae, 8'hbe: begin mem16 = 1; size = 1; end
					//8'h9f, 8'haf, 8'hbf: begin mem16 = 1; size = 1; end
					8'hce: begin mode = `IMMEDIATE; size = 1; end
					//8'hde, 8'hee, 8'hfe: begin mem16 = 1; size = 1; end
					//8'hdf, 8'hef, 8'hff: begin mem16 = 1; size = 1; end
				endcase
				casex( postbyte0)
					8'h9x, 8'hdx: mode = `DIRECT;
					8'hax, 8'hex: mode = `INDEXED;
					8'hbx, 8'hfx: mode = `EXTENDED;
				endcase
			end
	end
	
endmodule

/* Decodes the Effective Address postbyte
   to recover size of offset to load and post-incr/pre-decr info
 */
module decode_ea(
	input wire [7:0] eapostbyte,
	output reg noofs,
	output reg ofs8, // needs an 8 bit offset
	output reg ofs16, // needs an 16 bit offset
	output reg write_post, // needs to write back a predecr or post incr
	output wire isind // signals when the mode is indirect, the memory at the address is read to load the real address
	);
	
assign isind = (eapostbyte[7] & eapostbyte[4]) ? 1'b1:1'b0;
always @(*)
	begin
		noofs = 0;
		ofs8 = 0;
		ofs16 = 0;
		write_post = 0;
		casex (eapostbyte)
			8'b0xxxxxxx, 8'b1xx00100: noofs = 1;
			8'b1xxx1000, 8'b1xxx1100: ofs8 = 1;
			8'b1xxx1001, 8'b1xxx1101: ofs16 = 1;
			8'b1xx11111: ofs16 = 1; // extended indirect
			8'b1xxx00xx: write_post = 1;
		endcase
	end
endmodule

module decode_alu(
	input wire [7:0] opcode,
	input wire [7:0] postbyte0,
	input wire page2_valid, // is 1 when the postbyte0 was loaded and is page2 opcode
	input wire page3_valid, // is 1 when the postbyte0 was loaded and is page3 opcode
	output reg [4:0] alu_opcode,
	output reg [1:0] dec_alu_right_path_mod,
	output wire dest_flags
	);
// flags are written for alu opcodes as long as the opcode is not ANDCC or ORCC
assign dest_flags = (alu_opcode != `NOP) && (opcode != 8'h1a) && (opcode != 8'h1c);
always @(*)
	begin
		alu_opcode = `NOP;
		dec_alu_right_path_mod = `MOD_DEFAULT;
		casex (opcode)
			8'b1xxx_0000: alu_opcode = `SUB;
			8'b1xxx_0001: alu_opcode = `SUB; // CMP
			8'b1xxx_0010: alu_opcode = `SBC;
			8'b10xx_0011: alu_opcode = `SUB;
			8'b11xx_0011: alu_opcode = `ADD;
			8'b1xxx_0100: alu_opcode = `AND;
			8'b1xxx_0101: alu_opcode = `AND; // BIT
			8'b1xxx_0110: alu_opcode = `LD;
			8'b1xxx_0111: alu_opcode = `ST;
			8'b1xxx_1000: alu_opcode = `EOR;
			8'b1xxx_1001: alu_opcode = `ADC;
			8'b1xxx_1010: alu_opcode = `OR;
			8'b1xxx_1011: alu_opcode = `ADD;
			8'b10xx_1100: alu_opcode = `SUB; // CMP
			8'b11xx_1100: alu_opcode = `LD;
			8'b11xx_1101: alu_opcode = `LD;
			8'b1xxx_1110: alu_opcode = `LD;
			8'b1xxx_1111: alu_opcode = `ST;
			
			8'h00, 8'b01xx_0000: alu_opcode = `NEG;
			8'h03, 8'b01xx_0011: alu_opcode = `COM;
			8'h04, 8'b01xx_0100: alu_opcode = `LSR;
			8'h06, 8'b01xx_0110: alu_opcode = `ROR;
			8'h07, 8'b01xx_0111: alu_opcode = `ASR;
			8'h08, 8'b01xx_1000: alu_opcode = `LSL;
			8'h09, 8'b01xx_1001: alu_opcode = `ROL;
			8'h0a, 8'b01xx_1010: begin alu_opcode = `DEC; dec_alu_right_path_mod = `MOD_ONE; end // dec
			8'h0c, 8'b01xx_1100: begin alu_opcode = `INC; dec_alu_right_path_mod = `MOD_ONE; end // inc
			8'h0d, 8'b01xx_1101: alu_opcode = `AND;
			8'h0f, 8'b01xx_1111: begin alu_opcode = `LD; dec_alu_right_path_mod = `MOD_ZERO; end // CLR
			
			8'h19: alu_opcode = `DAA;
			8'h1a: alu_opcode = `OR;
			8'h1c: alu_opcode = `AND;
			8'h1d: alu_opcode = `SEXT;
			//8'h1e: alu_opcode = `EXG;
			8'b0011_000x: alu_opcode = `LEA;
			8'h3d: alu_opcode = `MUL;
		endcase
		if (page2_valid)
			casex (postbyte0)
				8'b10xx_0011,
				8'b10xx_1100: alu_opcode = `SUB; //CMP
				8'b1xxx_1110: alu_opcode = `LD;
				8'b1xxx_1111: alu_opcode = `ST;
			endcase
		if (page3_valid)
			casex (postbyte0)
				8'b10xx_0011,
				8'b10xx_1100: alu_opcode = `SUB; //CMP
				8'b1xxx_1110: alu_opcode = `LD;
				8'b1xxx_1111: alu_opcode = `ST;
			endcase
	end
	
endmodule
/* decodes the condition and checks the flags to see if it is met */
module test_condition(
	input wire [7:0] opcode,
	input wire [7:0] postbyte0,
	input wire page2_valid,
	input wire [7:0] CCR,
	output reg cond_taken
	);

wire [7:0] op = page2_valid ? postbyte0:opcode;
	
always @(*)
	begin
		cond_taken = 1'b0;
		if ((op == 8'h16) || (op == 8'h17) || (op == 8'h8D) ||
			(op == 8'h0e) || (op == 8'h6e) || (op == 8'h7e)) // jmp
			cond_taken = 1'b1; // LBRA/LBSR, BSR
		if (op[7:4] == 4'h2)
			case (op[3:0])
				4'h0: cond_taken = 1'b1; // BRA
				4'h1: cond_taken = 0; // BRN
				4'h2: cond_taken = !(`DFLAGC & `DFLAGZ); // BHI
				4'h3: cond_taken = `DFLAGC | `DFLAGZ; // BLS
				4'h4: cond_taken = !`DFLAGC; // BCC, BHS
				4'h5: cond_taken = `DFLAGC; // BCS, BLO
				4'h6: cond_taken = !`DFLAGZ; // BNE
				4'h7: cond_taken = `DFLAGZ; // BEQ
				4'h8: cond_taken = !`DFLAGV; // BVC
				4'h9: cond_taken = `DFLAGV; // BVS
				4'ha: cond_taken = !`DFLAGN; // BPL
				4'hb: cond_taken = `DFLAGN; // BMI
				4'hc: cond_taken = `DFLAGN == `DFLAGV; // BGE
				4'hd: cond_taken = `DFLAGN != `DFLAGV; // BLT
				4'he: cond_taken = (`DFLAGN == `DFLAGV) & (!`DFLAGZ); // BGT
				4'hf: cond_taken = (`DFLAGN != `DFLAGV) | (`DFLAGZ); // BLE
		endcase
	end
	
endmodule