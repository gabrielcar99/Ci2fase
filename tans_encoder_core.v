`timescale 1ns/1ps

// ============================================================================
// Modulo: tans_encoder_core
// Descricao: Nucleo do Encoder tANS (1 simbolo por ciclo de clock).
//            Executa apenas soma, deslocamento e mascaramento de bits
//            (sem multiplicacoes ou divisoes), consultando o banco de tabelas.
// Padrao: Verilog-2001 sintetizavel
// ============================================================================

module tans_encoder_core #(
    parameter L          = 16,
    parameter R          = 4,
    parameter SYM_WIDTH  = 2,
    parameter NB_WIDTH   = 3,
    parameter NB_PARAM_W = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // Controle de inicializacao de bloco
    input  wire                  init_en,
    input  wire [R:0]            init_state,   // Deve estar em [L, 2*L - 1]

    // Entrada de simbolos
    input  wire                  sym_valid,
    input  wire [SYM_WIDTH-1:0]  sym_in,
    input  wire                  sym_last,

    // Interface com o banco de registradores (tans_table_bank)
    output wire [SYM_WIDTH-1:0]  lut_sym_addr,
    input  wire [NB_PARAM_W-1:0] lut_sym_nb,
    input  wire [R-1:0]          lut_sym_off,
    output wire [R-1:0]          lut_enc_addr,
    input  wire [R:0]            lut_enc_data,

    // Saida por passo (bits variaveis extraidos do estado)
    output reg                   out_valid,
    output reg  [R-1:0]          out_bits,
    output reg  [NB_WIDTH-1:0]   out_nbits,
    output reg                   out_last,

    // Estado atual e sinalizacao de fim de bloco
    output reg  [R:0]            state_reg,
    output reg                   done
);

    localparam [R:0] DEFAULT_INIT_STATE = L;

    // Estado corrente usado no ciclo (permite init_en + sym_valid no mesmo ciclo)
    wire [R:0] cur_state = init_en ? init_state : state_reg;

    // 1) Consulta da tabela de simbolo
    assign lut_sym_addr = sym_in;

    // 2) Calculo de nbBits = (state + nb[s]) >> (R + 1)
    wire [NB_PARAM_W-1:0] state_ext = {{(NB_PARAM_W - (R + 1)){1'b0}}, cur_state};
    wire [NB_PARAM_W-1:0] nb_sum    = state_ext + lut_sym_nb;
    wire [NB_WIDTH-1:0]   cur_nbits = nb_sum[NB_PARAM_W-1 : R+1];

    // 3) Extracao dos cur_nbits menos significativos de cur_state
    wire [R:0]   bit_mask     = ({{R{1'b0}}, 1'b1} << cur_nbits) - {{R{1'b0}}, 1'b1};
    wire [R-1:0] cur_out_bits = cur_state[R-1:0] & bit_mask[R-1:0];

    // 4) Reducao do estado e calculo do indice na encodingTable
    wire [R:0]   x_tmp        = cur_state >> cur_nbits;
    wire [R-1:0] table_idx    = lut_sym_off + x_tmp[R-1:0];

    assign lut_enc_addr = table_idx;

    // 5) Atualizacao sincrona de estado e saidas
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= DEFAULT_INIT_STATE;
            out_valid <= 1'b0;
            out_bits  <= {R{1'b0}};
            out_nbits <= {NB_WIDTH{1'b0}};
            out_last  <= 1'b0;
            done      <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            out_last  <= 1'b0;
            done      <= 1'b0;

            if (init_en && !sym_valid) begin
                state_reg <= init_state;
            end else if (sym_valid) begin
                state_reg <= lut_enc_data;
                out_valid <= 1'b1;
                out_bits  <= cur_out_bits;
                out_nbits <= cur_nbits;
                out_last  <= sym_last;
                done      <= sym_last;
            end
        end
    end

endmodule
