module vga80x40 (
  input logic reset,
  input logic clk25MHz,
  output logic [11:0] TEXT_A,
  input logic [7:0] TEXT_D,
  output logic [11:0] FONT_A,
  input logic [7:0] FONT_D,
  input logic [7:0] ocrx,
  input logic [7:0] ocry,
  input logic [7:0] octl,
  output logic R,
  output logic G,
  output logic B,
  output logic hsync,
  output logic vsync
);

  logic R_int;
  logic G_int;
  logic B_int;
  logic hsync_int;
  logic vsync_int;

  logic blank;
  logic [9:0] hctr;
  logic [9:0] vctr;
  
  //character / pixel pos on screen
  logic [5:0] scry;
  logic [6:0] scrx;
  logic [3:0] chry;
  logic [2:0] chrx;

  logic losr_ce;
  logic losr_ld;
  logic losr_do;
  logic y; //luminance1

  /* control io register */ 
  logic [7:0] ctl;
  logic vga_en, cur_en, cur_mode, cur_blink, ctl_r, ctl_g, ctl_b;

  /* hsync generator */ 
  always_ff @(posedge clk25MHz, posedge reset) begin
    if(reset) hsync_int <= 1'b1;
    else if((hctr > 10'd663) && (hctr < 10'd757)) hsync_int <= 1'b0;
    else hsync_int <= 1'b1;
  end

  /* vsync generator */ 
  always_ff @(posedge clk25MHz, posedge reset) begin
    if(reset) vsync_int <= 1'b1;
    else if ((vctr > 10'd 499) && (vctr < 10'd502)) vsync_int <= 1'b0;
    else vsync_int <= 1'b1;
  end

  /* blank signal */ 
  assign blank = !((hctr < 10'd8) || (hctr > 10'd647) || (vctr > 10'd479));

  /* FFs for sync of RGB signal */ 
  always_ff @(posedge clk25MHz, posedge reset) begin
    if(reset) begin
      R <= 1'b0;
      G <= 1'b0;
      B <= 1'b0;
    end
    else begin
      R <= R_int;
      G <= G_int;
      B <= B_int;
    end
  end

  /* control registers */ 

  assign cur_mode = octl[4];
  assign cur_blink = octl[5];
  assign cur_en = octl[6];
  assign vga_en = octl[7];
  assign ctl_r = octl[2];
  assign ctl_g = octl[1];
  assign ctl_b = octl[0];

  /* counters */ 
  logic hctr_ce, hctr_rs, vctr_ce, vctr_rs;
  logic chrx_ce, chrx_rs, chry_ce, chry_rs;
  logic scrx_ce, scrx_rs, scry_ce, scry_rs;
  logic hctr_639, vctr_479, chrx_007, chry_011, scrx_079;

  logic [12:0] ram_tmp, rom_tmp;

  ctrm #(.M(794)) U_HCTR (
    .reset(reset),
    .clk(clk25MHz),
    .ce(hctr_ce),
    .rs(hctr_rs),
    .do(hctr)
  );

  ctrm #(.M(525)) U_VCTR (
    .reset(reset),
    .clk(clk25MHz),
    .ce(vctr_ce),
    .rs(vctr_rs),
    .do(vctr)
  );

  assign hctr_ce = 1'b1;
  assign hctr_rs = (hctr == 10'd793);
  assign vctr_ce = (hctr == 10'd663);
  assign vctr_rs = (vctr == 10'd524);

  ctrm #(.M(8)) U_CHRX
  (
    .reset(reset),
    .clk(clk25MHz),
    .ce(chrx_ce),
    .rs(chrx_rs),
    .do(chrx)
  );

  ctrm #(.M(8)) U_CHRY
  (
    .reset(reset),
    .clk(clk25MHz),
    .ce(chry_ce),
    .rs(chry_rs),
    .do(chry)
  );

  ctrm #(.M(8)) U_SCRX
  (
    .reset(reset),
    .clk(clk25MHz),
    .ce(scrx_ce),
    .rs(scrx_rs),
    .do(scrx)
  );

  ctrm #(.M(8)) U_SCRY
  (
    .reset(reset),
    .clk(clk25MHz),
    .ce(scry_ce),
    .rs(scry_rs),
    .do(scry)
  );

  assign hctr_639 = (hctr == 10'd639);
  assign vctr_479 = (vctr == 10'd479);
  assign chrx_007 = (chrx == 3'd7);
  assign chry_011 = (chry == 4'd11);
  assign scrx_079 = (scrx == 7'd79);


  assign chrx_rs = chrx_007 || hctr_639;
  assign chry_rs = chry_011 || vctr_479;
  assign scrx_rs = hctr_639;
  assign scry_rs = vctr_479;

  assign chrx_ce = blank;
  assign scrx_ce = chrx_007;
  assign chry_ce = hctr_639 && blank;
  assign scry_ce = chry_011 && hctr_639;

  assign ram_tmp = scry * 80 + scrx;
  assign TEXT_A = ram_tmp;

  assign rom_tmp = TEXT_D * 12 + chry;
  assign FONT_A = rom_tmp;

  /* losr */
  losr #(.N(8)) U_LOSR (
    .reset(reset),
    .clk(clk25MHz),
    .ce(losr_ce),
    .load(losr_ld),
    .do(losr_do),
    .di(FONT_D)
  );

  assign losr_ce = blank
  assign losr_ld = (chrx == 3'd7);

  assign R_int = (ctl_r && y) && blank;
  assign G_int = (ctl_g && y) && blank;
  assign B_int = (ctl_b && y) && blank;

  assign hsync = hsync_int && vga_en;
  assign vsync = vsync_int && vga_en;

  //cursor
  logic smal, curen2, slowclk, curpos, yint;
  logic [6:0] crx_tmp, crx;
  logic [5:0] cry_tmp, cry;
  logic [22:0] counter;

  always_ff @(posedge clk25MHz) begin
    counter <= counter + 1;
  end

  assign slowclk = counter[22];

  assign crx = ocrx[6:0];
  assign cry = ocry[5:0];

  assign curpos = ((scry == cry) && (scrx == crx));
  assign smal = (chry > 4'd8);
  assign curen2 = ((slowclk || (!cur_blink)) && cur_en);
  assign yint = (cur_mode == 1'b0);
  assign y = ((yint && curpos && curen2) ^ losr_do);

endmodule