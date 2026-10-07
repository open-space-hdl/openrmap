---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Authorisation of the RMAP Target (TG-2): checks a decoded command header against the packet type,
-- the command codes, the logical addresses, the key, the read-modify-write length, the verify
-- buffer size, the address windows with their permissions, the AXI address range and the alignment
-- of single-address accesses. The result is the first failing check in the order of architecture
-- decision D9, two cycles after Start.
--
-- Documentation: hdl/omap_target/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.omap_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_target_auth is
    generic (
        AxiAddrWidth_g : positive range 12 to 40 := 32;
        AxiDataWidth_g : positive                := 32;
        BufferBytes_g  : positive                := 256;
        Windows_g      : natural range 0 to 8    := 4
    );
    port (
        Clk         : in    std_logic;
        Rst         : in    std_logic;
        -- Configuration
        Cfg_La0     : in    std_logic_vector(7 downto 0);
        Cfg_La0En   : in    std_logic;
        Cfg_La1     : in    std_logic_vector(7 downto 0);
        Cfg_La1En   : in    std_logic;
        Cfg_DefLaEn : in    std_logic;
        Cfg_Key     : in    std_logic_vector(7 downto 0);
        Cfg_KeyEn   : in    std_logic;
        Cfg_Win     : in    WinCfgArray_t(0 to Windows_g - 1);
        -- Check of one header
        Start       : in    std_logic;
        Hdr         : in    CmdHeader_t;
        Done        : out   std_logic;
        Discard     : out   std_logic; -- Reserved packet type: discard without reply
        Status      : out   std_logic_vector(7 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of omap_target_auth is

    constant WordBytes_c : positive := AxiDataWidth_g / 8;

    type TwoProcess_r is record
        Stage1  : std_logic;
        Stage2  : std_logic;
        Kind    : CmdKind_t;
        Discard : std_logic;
        LaOk    : std_logic;
        KeyOk   : std_logic;
        RmwLen  : std_logic;
        Overrun : std_logic;
        Aligned : std_logic;
        AxiOk   : std_logic;
        WinOk   : std_logic;
        Status  : std_logic_vector(7 downto 0);
        DiscOut : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable Len_v    : unsigned(23 downto 0);
        variable Span_v   : unsigned(40 downto 0);
        variable First_v  : unsigned(40 downto 0);
        variable Last_v   : unsigned(40 downto 0);
        variable Kind_v   : CmdKind_t;
        variable Single_v : boolean;
        variable Perm_v   : boolean;
    begin
        v        := r;
        v.Stage1 := Start;
        v.Stage2 := r.Stage1;

        -- Stage 1: the individual checks
        Kind_v   := cmdKind(cmdCode(Hdr.Instr));
        Len_v    := unsigned(Hdr.Len);
        Single_v := Hdr.Instr(InstrInc_c) = '0';
        v.Kind   := Kind_v;

        -- ECSS 5.3.3.4.6: reserved packet types are discarded
        v.Discard := Hdr.Instr(InstrReserved_c);

        -- ECSS 5.3.3.5.3: logical addresses
        if (Cfg_La0En = '1' and Hdr.Tla = Cfg_La0) or (Cfg_La1En = '1' and Hdr.Tla = Cfg_La1) or
           (Cfg_DefLaEn = '1' and Hdr.Tla = DefaultLa_c) then
            v.LaOk := '1';
        else
            v.LaOk := '0';
        end if;

        -- ECSS 5.3.3.5.2: key
        if Cfg_KeyEn = '0' or Hdr.Key = Cfg_Key then
            v.KeyOk := '1';
        else
            v.KeyOk := '0';
        end if;

        -- ECSS 5.5.1.12d: read-modify-write lengths 0, 2, 4, 6 and 8
        if Kind_v = CmdRmw and (Len_v > 8 or Len_v(0) = '1') then
            v.RmwLen := '1';
        else
            v.RmwLen := '0';
        end if;

        -- ECSS 5.3.3.6.3: verified writes fit into the verify buffer
        if Kind_v = CmdWrite and Hdr.Instr(InstrVerify_c) = '1' and Len_v > BufferBytes_g then
            v.Overrun := '1';
        else
            v.Overrun := '0';
        end if;

        -- Bytes accessed: one memory word for single-address accesses, n = Data Length / 2 for a
        -- read-modify-write, Data Length otherwise; at least one byte (address of a zero-length command). The
        -- read-modify-write command code has the increment bit set, so it is never a single-address access.
        if Single_v then
            Span_v := to_unsigned(WordBytes_c, 41);
        elsif Kind_v = CmdRmw then
            Span_v := resize(Len_v(23 downto 1), 41);
        else
            Span_v := resize(Len_v, 41);
        end if;
        if Span_v = 0 then
            Span_v := to_unsigned(1, 41);
        end if;
        First_v := resize(unsigned(Hdr.Addr), 41);
        Last_v  := First_v + Span_v - 1;

        -- Single-address accesses: aligned to the memory word, length a multiple of it (architecture D7)
        if Single_v and (unsigned(Hdr.Addr) mod WordBytes_c /= 0 or Len_v mod WordBytes_c /= 0) then
            v.Aligned := '0';
        else
            v.Aligned := '1';
        end if;

        -- AXI address range (architecture D4)
        if Last_v < shift_left(to_unsigned(1, 41), AxiAddrWidth_g) then
            v.AxiOk := '1';
        else
            v.AxiOk := '0';
        end if;

        -- Address windows (architecture D8)
        if Windows_g = 0 then
            v.WinOk := '1';
        else
            v.WinOk := '0';

            for w in 0 to Windows_g - 1 loop

                case Kind_v is

                    when CmdRead =>
                        Perm_v := Cfg_Win(w).Read = '1';

                    when CmdWrite =>
                        Perm_v := Cfg_Win(w).Write = '1' and
                                  (Cfg_Win(w).VerifiedOnly = '0' or Hdr.Instr(InstrVerify_c) = '1');

                    when CmdRmw =>
                        Perm_v := Cfg_Win(w).Rmw = '1';

                    when others =>
                        Perm_v := false;

                end case;

                if Single_v and Cfg_Win(w).Single = '0' then
                    Perm_v := false;
                end if;
                if Cfg_Win(w).Enable = '1' and Perm_v and First_v >= resize(unsigned(Cfg_Win(w).Base), 41) and
                   Last_v <= resize(unsigned(Cfg_Win(w).Last), 41) then
                    v.WinOk := '1';
                end if;
            end loop;

        end if;

        -- Stage 2: priority of the status codes (architecture D9)
        v.DiscOut := r.Discard;
        if r.Kind = CmdInvalid then
            v.Status := StatusUnused_c;
        elsif r.LaOk = '0' then
            v.Status := StatusTla_c;
        elsif r.KeyOk = '0' then
            v.Status := StatusKey_c;
        elsif r.RmwLen = '1' then
            v.Status := StatusRmwLength_c;
        elsif r.Overrun = '1' then
            v.Status := StatusVerifyOverrun_c;
        elsif r.Aligned = '0' or r.AxiOk = '0' or r.WinOk = '0' then
            v.Status := StatusNotAuth_c;
        else
            v.Status := StatusOk_c;
        end if;

        r_next <= v;
    end process;

    Done    <= r.Stage2;
    Discard <= r.DiscOut;
    Status  <= r.Status;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Stage1 <= '0';
                r.Stage2 <= '0';
            end if;
        end if;
    end process;

end architecture;
