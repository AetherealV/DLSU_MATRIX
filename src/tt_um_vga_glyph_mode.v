/*
 * Copyright (c) 2024-2025 James Ross
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_glyph_mode(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // VGA signals
    wire hsync, vsync, display_on;
    wire [10:0] hpos;
    wire [9:0] vpos;

    // TinyVGA PMOD mapping
    assign uo_out = {hsync, RGB[0], RGB[2], RGB[4], vsync, RGB[1], RGB[3], RGB[5]};

    // Unused outputs
    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;

    wire [7:0] xb = hpos[10:3];
    wire [6:0] x_mix = {xb[7] ^ xb[3], xb[1], xb[4], xb[1], xb[6], xb[0], xb[2]};
    wire [2:0] g_x = hpos[2:0];

    wire [5:0] yb;
    wire [3:0] _unused;
    assign {_unused, yb} = vpos / 10'd12;

    wire [5:0] g_unused;
    wire [3:0] g_y;
    assign {g_unused, g_y} = vpos - {yb, 3'b000} - {1'b0, yb, 2'b00};

    wire hl;
    wire _unused_ok = &{ena, ui_in[5:2], uio_in, _unused, g_unused};

    reg [9:0] frame;
    reg rst_drop;

    // VGA output generator
    hvsync_generator hvsync_gen(
        .clk(clk),
        .reset(~rst_n),
        .mode(ui_in[7:6]),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(hpos),
        .vpos(vpos)
    );

    // 30-character sequence: "DE LA SALLE UNIVERSITY MANILA "
    wire [4:0] char_idx = (xb + yb) % 5'd30;
    reg [5:0] text_rom;

    always @(*) begin
        case (char_idx)
            5'd0:  text_rom = 6'd3;   // D
            5'd1:  text_rom = 6'd4;   // E
            5'd2:  text_rom = 6'd26;  // <SPACE>
            5'd3:  text_rom = 6'd11;  // L
            5'd4:  text_rom = 6'd0;   // A
            5'd5:  text_rom = 6'd26;  // <SPACE>
            5'd6:  text_rom = 6'd18;  // S
            5'd7:  text_rom = 6'd0;   // A
            5'd8:  text_rom = 6'd11;  // L
            5'd9:  text_rom = 6'd11;  // L
            5'd10: text_rom = 6'd4;   // E
            5'd11: text_rom = 6'd26;  // <SPACE>
            5'd12: text_rom = 6'd20;  // U
            5'd13: text_rom = 6'd13;  // N
            5'd14: text_rom = 6'd8;   // I
            5'd15: text_rom = 6'd21;  // V
            5'd16: text_rom = 6'd4;   // E
            5'd17: text_rom = 6'd17;  // R
            5'd18: text_rom = 6'd18;  // S
            5'd19: text_rom = 6'd8;   // I
            5'd20: text_rom = 6'd19;  // T
            5'd21: text_rom = 6'd24;  // Y
            5'd22: text_rom = 6'd26;  // <SPACE>
            5'd23: text_rom = 6'd12;  // M
            5'd24: text_rom = 6'd0;   // A
            5'd25: text_rom = 6'd13;  // N
            5'd26: text_rom = 6'd8;   // I
            5'd27: text_rom = 6'd11;  // L
            5'd28: text_rom = 6'd0;   // A
            5'd29: text_rom = 6'd26;  // <SPACE>
            default: text_rom = 6'd26;
        endcase
    end

    wire [5:0] glyph_index = text_rom;

    // Glyphs
    glyphs_rom glyphs(
        .c(glyph_index),
        .y(g_y),
        .x(g_x),
        .pixel(hl)
    );

    // Palette
    wire [5:0] color;
    wire [2:0] y_col;

    palette_rom palettes(
        .cid(y_col),
        .pid(ui_in[1:0]),
        .color(color)
    );

    wire [1:0] a = xb[1:0];
    wire [3:0] b = xb[5:2];
    wire [2:0] d = xb[3:2] + 2'd3;

    // Column rain animation features
    wire s = ^xb[6:0];
    wire n = xb[1] ^ xb[3] ^ xb[5];
    wire [6:0] v = (s ? frame[8:2] : frame[9:3]) - yb - x_mix;
    wire [3:0] c = {1'b0, a} + d;
    wire [6:0] e = {3'b000, b} << c;
    wire [6:0] f = v & e;
    wire [6:0] x = v >> a;
    assign y_col = ~x[2:0];

    wire [9:0] drop = {1'b0, yb, 3'd0} >> s;
    wire drop_bit = ({3'd0, x_mix} + drop > frame) & ~rst_drop;
    wire [5:0] glyph_color = {6{drop_bit}} ^ color;
    wire [5:0] z = (&(~v[2:0]) & &(y_col)) ? 6'd63 : glyph_color;
    wire [5:0] RGB = (display_on & hl & ~(|f | n | drop_bit)) ? z : 6'd0;

    always @(posedge vsync or negedge rst_n) begin
        if (~rst_n) begin
            rst_drop <= 0;
            frame    <= 0;
        end else begin
            if (&frame)
                rst_drop <= 1;
            frame <= frame + 1'b1;
        end
    end

endmodule
