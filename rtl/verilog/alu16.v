/* 
 * (c) 2013 Alejandro Paz
 *
 *
 * An alu core
 *
 * ADD, ADC, DAA, SUB, SBC, COM, NEG, CMP, ASR, ASL, ROR, ROL, RCR, RCL
 *
 *
 *
 */
`include "defs.v"
module alu16(
	input wire clk,
	input wire [15:0] a_in,
	input wire [15:0] b_in,
	input wire [7:0] CCR, /* condition code register */
	input wire [4:0] opcode_in, /* ALU opcode */
	input wire sz_in, /* size, low 8 bit, high 16 bit */
	output reg [15:0] q_out, /* ALU result */
	output reg [7:0] CCRo
	);

wire c_in, n_in, v_in, z_in, h_in;
assign c_in = CCR[0]; /* carry flag */
assign n_in = CCR[3]; /* neg flag */
assign v_in = CCR[1]; /* overflow flag */
assign z_in = CCR[2]; /* zero flag */
assign h_in = CCR[5]; /* halb-carry flag */


wire [7:0] add8_r, adc8_r, sub8_r, sbc8_r, com8_r, neg8_r;
wire [7:0] asr8_r, shr8_r, shl8_r, ror8_r, rol8_r, and8_r, or8_r, eor8_r;
wire [15:0] add16_r, adc16_r, sub16_r, sbc16_r, com16_r, neg16_r;
wire [15:0] asr16_r, shr16_r, shl16_r, ror16_r, rol16_r, and16_r, or16_r, eor16_r, mul16_r;
wire [3:0] daa8l_r, daa8h_r;
wire daa_lnm9;

wire [7:0] add8_w, adc8_w, com8_w, neg8_w, sub8_w, sbc8_w;
wire [7:0] asr8_w, shr8_w, shl8_w, ror8_w, rol8_w, and8_w, or8_w, eor8_w;
wire [15:0] add16_w, adc16_w, com16_w, neg16_w, sub16_w, sbc16_w;
wire [15:0] asr16_w, shr16_w, shl16_w, ror16_w, rol16_w, and16_w, or16_w, eor16_w, mul16_w;

wire cadd8_w, cadc8_w, csub8_w, csbc8_w;
wire cadd16_w, cadc16_w, csub16_w, csbc16_w;

wire cadd8_r, cadc8_r, csub8_r, csbc8_r, ccom8_r, cneg8_r;
wire casr8_r, cshr8_r, cshl8_r, cror8_r, crol8_r, cand8_r, cdaa8_r;
wire cadd16_r, cadc16_r, csub16_r, csbc16_r, ccom16_r, cneg16_r;
wire casr16_r, cshr16_r, cshl16_r, cror16_r, crol16_r, cand16_r, cmul16_r;
wire vadd8_r, vadc8_r, vsub8_r, vsbc8_r, vcom8_r, vneg8_r;
wire vasr8_r, vshr8_r, vshl8_r, vror8_r, vrol8_r, vand8_r;
wire vadd16_r, vadc16_r, vsub16_r, vsbc16_r, vcom16_r, vneg16_r;
wire vasr16_r, vshr16_r, vshl16_r, vror16_r, vrol16_r, vand16_r;

assign { cadd8_w, add8_w }   = { 1'b0, a_in[7:0] } + { 1'b0, b_in[7:0] };
assign { cadd16_w, add16_w } = { 1'b0, a_in[15:0] } + { 1'b0, b_in[15:0] };
assign { cadc8_w, adc8_w }   = { 1'b0, a_in[7:0] } + { 1'b0, b_in[7:0] } + { 8'h0, c_in };
assign { cadc16_w, adc16_w } = { 1'b0, a_in[15:0] } + { 1'b0, b_in[15:0] } + { 16'h0, c_in };

assign { csub8_w, sub8_w }   = { 1'b0, a_in[7:0] } - { 1'b0, b_in[7:0] };
assign { csub16_w, sub16_w } = { 1'b0, a_in[15:0] } - { 1'b0, b_in[15:0] };
assign { csbc8_w, sbc8_w }   = { 1'b0, a_in[7:0] } - { 1'b0, b_in[7:0] } - { 8'h0, c_in };
assign { csbc16_w, sbc16_w } = { 1'b0, a_in[15:0] } - { 1'b0, b_in[15:0] } - { 16'h0, c_in };

assign com8_w = ~a_in[7:0];
assign com16_w = ~a_in[15:0];
assign neg8_w = 8'h0 - a_in[7:0];
assign neg16_w = 16'h0 - a_in[15:0];

assign asr8_w = { a_in[7], a_in[7:1] };
assign asr16_w = { a_in[15], a_in[15:1] };

assign shr8_w = { 1'b0, a_in[7:1] };
assign shr16_w = { 1'b0, a_in[15:1] };

assign shl8_w = { a_in[6:0], 1'b0 };
assign shl16_w = { a_in[14:0], 1'b0 };

assign ror8_w = { c_in, a_in[7:1] };
assign ror16_w = { c_in, a_in[15:1] };

assign rol8_w = { a_in[6:0], c_in };
assign rol16_w = { a_in[14:0], c_in };

assign and8_w = a_in[7:0] & b_in[7:0];
assign and16_w = a_in[15:0] & b_in[15:0];

assign or8_w = a_in[7:0] | b_in[7:0];
assign or16_w = a_in[15:0] | b_in[15:0];

assign eor8_w = a_in[7:0] ^ b_in[7:0];
assign eor16_w = a_in[15:0] ^ b_in[15:0];
assign mul16_w = a_in[7:0] * b_in[7:0];

		// ADD, ADC
assign { cadd8_r, add8_r } = { cadd8_w, add8_w };
assign vadd8_r = (a_in[7] & b_in[7] & (~add8_w[7])) | ((~a_in[7]) & (~b_in[7]) & add8_w[7]);
assign { cadd16_r, add16_r } = { cadd16_w, add16_w };
assign vadd16_r = (a_in[15] & b_in[15] & (~add16_w[15])) | ((~a_in[15]) & (~b_in[15]) & add16_w[15]);
assign { cadc8_r, adc8_r } = { cadd8_w, add8_w };
assign vadc8_r = (a_in[7] & b_in[7] & (~add8_w[7])) | ((~a_in[7]) & (~b_in[7]) & adc8_w[7]);
assign { cadc16_r, adc16_r } = { cadd16_w, add16_w };
assign vadc16_r = (a_in[15] & b_in[15] & (~add16_w[15])) | ((~a_in[15]) & (~b_in[15]) & adc16_w[15]);
		// SUB, SUBC
assign { csub8_r, sub8_r } = { csub8_w, sub8_w };
assign vsub8_r = (a_in[7] & (~b_in[7]) & (~sub8_w[7])) | ((~a_in[7]) & b_in[7] & sub8_w[7]);
assign { csub16_r, sub16_r } = { csub16_w, sub16_w };
assign vsub16_r = (a_in[15] & b_in[15] & (~add16_w[15])) | ((~a_in[15]) & b_in[15] & sub16_w[15]);
assign { csbc8_r, sbc8_r } = { csbc8_w, sbc8_w };
assign vsbc8_r = (a_in[7] & b_in[7] | (~sbc8_w[7])) | ((~a_in[7]) & b_in[7] & sbc8_w[7]);
assign { csbc16_r, sbc16_r } = { csbc16_w, sbc16_w };
assign vsbc16_r = (a_in[15] & b_in[15] & (~sbc16_w[15])) | ((~a_in[15]) & b_in[15] & sbc16_w[15]);
		// COM
assign com8_r = com8_w;
assign ccom8_r = com8_w != 8'h0 ? 1'b1:1'b0;
assign vcom8_r = 1'b0;
assign com16_r = com16_w;
assign ccom16_r = com16_w != 16'h0 ? 1'b1:1'b0;
assign vcom16_r = 1'b0;
		// NEG
assign neg8_r = neg8_w;
assign cneg8_r = neg8_w[7] | neg8_w[6] | neg8_w[5] | neg8_w[4] | neg8_w[3] | neg8_w[2] | neg8_w[1] | neg8_w[0];
assign vneg8_r = neg8_w[7] & (~neg8_w[6]) & (~neg8_w[5]) & (~neg8_w[4]) & (~neg8_w[3]) & (~neg8_w[2]) & (~neg8_w[1]) & (~neg8_w[0]);
assign neg16_r = neg16_w;
assign vneg16_r = neg16_w[15] & (~neg16_w[14]) & (~neg16_w[13]) & (~neg16_w[12]) & (~neg16_w[11]) & (~neg16_w[10]) & (~neg16_w[9]) & (~neg16_w[8]) & (~neg16_w[7]) & (~neg16_w[6]) & (~neg16_w[5]) & (~neg16_w[4]) & (~neg16_w[3]) & (~neg16_w[2]) & (~neg16_w[1]) & (~neg16_w[0]);
assign cneg16_r = neg16_w[15] | neg16_w[14] | neg16_w[13] | neg16_w[12] | neg16_w[11] | neg16_w[10] | neg16_w[9] & neg16_w[8] | neg16_w[7] | neg16_w[6] | neg16_w[5] | neg16_w[4] | neg16_w[3] | neg16_w[2] | neg16_w[1] | neg16_w[0];
		// ASR
assign asr8_r = asr8_w;
assign casr8_r = a_in[0];
assign vasr8_r = a_in[0] ^ asr8_w[7];
assign asr16_r = asr16_w;
assign casr16_r = a_in[0];
assign vasr16_r = a_in[0] ^ asr16_w[15];
		// SHR
assign shr8_r = shr8_w;
assign cshr8_r = a_in[0];
assign vshr8_r = a_in[0] ^ shr8_w[7];
assign shr16_r = shr16_w;
assign cshr16_r = a_in[0];
assign vshr16_r = a_in[0] ^ shr16_w[15];
		// SHL
assign shl8_r = shl8_w;
assign cshl8_r = a_in[7];
assign vshl8_r = a_in[7] ^ shl8_w[7];
assign shl16_r = shl16_w;
assign cshl16_r = a_in[15];
assign vshl16_r = a_in[15] ^ shl16_w[15];
		// ROR
assign ror8_r = ror8_w;
assign cror8_r = a_in[0];
assign vror8_r = a_in[0] ^ shr8_w[7];
assign ror16_r = ror16_w;
assign cror16_r = a_in[0];
assign vror16_r = a_in[0] ^ ror16_w[15];
		// ROL
assign rol8_r = shl8_w;
assign crol8_r = a_in[7];
assign vrol8_r = a_in[7] ^ rol8_w[7];
assign rol16_r = rol16_w;
assign crol16_r = a_in[15];
assign vrol16_r = a_in[15] ^ rol16_w[15];
		// AND
assign and8_r = and8_w;
assign cand8_r = c_in;
assign vand8_r = 1'b0;
assign and16_r = and16_w;
assign cand16_r = c_in;
assign vand16_r = 1'b0;
		// OR
assign or8_r = or8_w;
assign or16_r = or16_w;
		// EOR
assign eor8_r = eor8_w;
assign eor16_r = eor16_w;
		// MUL
assign mul16_r = mul16_w;
assign cmul16_r = mul16_w[7];
		// DAA
assign daa_lnm9 = (a_in[3:0] > 9);
assign daa8l_r = (daa_lnm9 | h_in ) ? a_in[3:0] + 4'h6:a_in[3:0];
assign daa8h_r = ((a_in[7:4] > 9) || (c_in == 1'b1) || (a_in[7] & daa_lnm9)) ? a_in[7:4] + 4'h6:a_in[7:4];
assign cdaa8_r = daa8h_r < a_in[7:4];

reg c8, h8, n8, v8, z8, c16, n16, v16, z16;
reg [7:0] q8;
reg [15:0] q16;
		
always @(*)
	begin
		q8 = 8'h0;
		q16 = 16'h0;
		c8 = c_in;
		h8 = h_in;
		v8 = v_in;
		c16 = c_in;
		v16 = v_in;
		case (opcode_in)
			`ADD:
				begin
					q8 = add8_r;
					c8 = cadd8_r;
					v8 = vadd8_r;
					q16 = add16_r;
					c16 = cadd16_r;
					v16 = vadd16_r;
				end
			`ADC:
				begin
					q8 = adc8_r;
					c8 = cadc8_r;
					v8 = vadc8_r;
					q16 = adc16_r;
					c16 = cadc16_r;
					v16 = vadc16_r;
				end
			`CMP, `SUB: // for CMP no register result is written back
				begin
					q8 = sub8_r;
					c8 = csub8_r;
					v8 = vsub8_r;
					q16 = sub16_r;
					c16 = csub16_r;
					v16 = vsub16_r;
				end
			`SBC:
				begin
					q8 = sbc8_r;
					c8 = csbc8_r;
					v8 = vsbc8_r;
					q16 = sbc16_r;
					c16 = csbc16_r;
					v16 = vsbc16_r;
				end
			`COM:
				begin
					q8 = com8_r;
					c8 = com8_r;
					v8 = vcom8_r;
					q16 = com16_r;
					c16 = ccom16_r;
					v16 = vcom16_r;
				end
			`NEG:
				begin
					q8 = neg8_r;
					c8 = cneg8_r;
					v8 = vneg8_r;
					q16 = neg16_r;
					c16 = cneg16_r;
					v16 = vneg16_r;
				end
			`ASR:
				begin
					q8 = asr8_r;
					c8 = casr8_r;
					v8 = vasr8_r;
					q16 = asr16_r;
					c16 = casr16_r;
					v16 = vasr16_r;
				end
			`LSR:
				begin
					q8 = shr8_r;
					c8 = cshr8_r;
					v8 = vshr8_r;
					q16 = shr16_r;
					c16 = cshr16_r;
					v16 = vshr16_r;
				end
			`LSL:
				begin
					q8 = shl8_r;
					c8 = cshl8_r;
					v8 = vshl8_r;
					q16 = shl16_r;
					c16 = cshl16_r;
					v16 = vshl16_r;
				end
			`ROR:
				begin
					q8 = ror8_r;
					c8 = cror8_r;
					v8 = vror8_r;
					q16 = ror16_r;
					c16 = cror16_r;
					v16 = vror16_r;
				end
			`ROL:
				begin
					q8 = rol8_r;
					c8 = crol8_r;
					v8 = vrol8_r;
					q16 = rol16_r;
					c16 = crol16_r;
					v16 = vrol16_r;
				end
			`AND:
				begin
					q8 = and8_r;
					c8 = cand8_r;
					v8 = vand8_r;
`ifdef HD6309
					q16 = and16_r;
					c16 = cand16_r;
					v16 = vand16_r;
`endif
					end
			`OR:
				begin
					q8 = or8_r;
					c8 = cand8_r;
					v8 = vand8_r;
`ifdef HD6309
					q16 = or16_r;
					c16 = cand16_r;
					v16 = vand16_r;
`endif
				end
			`EOR:
				begin
					q8 = eor8_r;
					c8 = cand8_r;
					v8 = vand8_r;
`ifdef HD6309
					q16 = eor16_r;
					c16 = cand16_r;
					v16 = vand16_r;
`endif
				end
			`DAA:
				begin // V is undefined, so we don't touch it
					q8 = { daa8h_r, daa8l_r };
					c8 = cdaa8_r;
				end
			`MUL:
				begin
					q16 = mul16_r;
					c16 = cmul16_r;
				end
			`LD:
				begin
					v8 = 0;
					v16 = 0;
					q8 = b_in[7:0];
					q16 = b_in[15:0];
				end
			`ST:
				begin
					q8 = a_in[7:0];
					q16 = a_in[15:0];
				end
			`T816: // zero extend 8 -> 16
				begin
					q16 = { 8'h0, b_in[7:0] };
				end	
			`T168L: // 16L -> 8
				begin
					q8 = b_in[7:0];
				end	
			`T168H: // 16L -> 8
				begin
					q8 = b_in[15:8];
				end	
			`SEXT: // sign extend
				begin
					q16 = { b_in[7] ? 8'hff:8'h00, b_in[7:0] };
				end
		endcase
	end

reg [7:0] regq8;
reg [15:0] regq16;
reg reg_n_in, reg_z_in;
/* register before second mux */
always @(posedge clk)
	begin
		regq8 <= q8;
		regq16 <= q16;
		reg_n_in <= n_in;
		reg_z_in <= z_in;
	end

/* Negative & zero flags */	
always @(*)
	begin
		n8 = regq8[7];
		z8 = regq8 == 8'h0;
		n16 = regq16[15];
		z16 = regq16 == 16'h0;
		case (opcode_in)
			`ADD:
				begin
				end
			`ADC:
				begin
				end
			`CMP, `SUB: // for CMP no register result is written back
				begin
				end
			`SBC:
				begin
				end
			`COM:
				begin
				end
			`NEG:
				begin
				end
			`ASR:
				begin
				end
			`LSR:
				begin
				end
			`LSL:
				begin
				end
			`ROR:
				begin
				end
			`ROL:
				begin
				end
			`AND:
				begin
				end
			`OR:
				begin
				end
			`EOR:
				begin
				end
			`DAA:
				begin // V is undefined, so we don't touch it
				end
			`MUL:
				begin
					n16 = reg_n_in;
					z16 = reg_z_in;
				end
			`LD:
				begin
				end
			`ST:
				begin
				end
			`T816: // zero extend 8 -> 16
				begin
					n16 = reg_n_in;
					z16 = reg_z_in;
				end	
			`T168L: // 16L -> 8
				begin
					n8 = reg_n_in;
					z8 = reg_z_in;
				end	
			`T168H: // 16L -> 8
				begin
					n8 = reg_n_in;
					z8 = reg_z_in;
				end	
			`SEXT: // sign extend
				begin
					n16 = reg_n_in;
					z16 = reg_z_in;
				end
		endcase
	end


always @(*)
	begin
		q_out[15:8] = regq16[15:8];
		if (sz_in)
			q_out[7:0] = regq16[7:0];
		else
			q_out[7:0] = regq8;
		
		case (opcode_in)
			`ORCC:
				CCRo = CCR | b_in[7:0];
			`ANDCC:
				CCRo = CCR & b_in[7:0];
			default:
				if (sz_in) // 16 bit
					CCRo = { CCR[7:4], n16, z16, v16, c16 };
				else
					CCRo = { CCR[7:6], CCR[5], h8, n8, z8, v8, c8 };
		endcase
	end

initial
	begin
	end
endmodule


/*
                            TERMS OF USE: MIT License

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
*/