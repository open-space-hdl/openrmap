---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- AXI memory model: behavioural AXI4 slave with INCR bursts, write strobes and up to 16 queued
-- commands per direction. The memory, the error ranges (SLVERR responses), the backpressure and the
-- statistics are those of instance Index_g of omap_tb_memvar_pkg.Mem_v. Bytes in a write error range
-- are not written. Ready and valid signals are held low at random in the configured share of cycles.
--
-- Documentation: hdl/omap_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library work;
    use work.omap_tb_memvar_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_tb_axi_ram is
    generic (
        Index_g     : natural;
        AddrWidth_g : positive := 32;
        DataWidth_g : positive := 32
    );
    port (
        Clk     : in    std_logic;
        Rst     : in    std_logic := '0'; -- Drops all outstanding transactions
        AwAddr  : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        AwLen   : in    std_logic_vector(7 downto 0);
        AwSize  : in    std_logic_vector(2 downto 0);
        AwBurst : in    std_logic_vector(1 downto 0);
        AwValid : in    std_logic;
        AwReady : out   std_logic;
        WData   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        WStrb   : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        WLast   : in    std_logic;
        WValid  : in    std_logic;
        WReady  : out   std_logic;
        BResp   : out   std_logic_vector(1 downto 0);
        BValid  : out   std_logic;
        BReady  : in    std_logic;
        ArAddr  : in    std_logic_vector(AddrWidth_g - 1 downto 0);
        ArLen   : in    std_logic_vector(7 downto 0);
        ArSize  : in    std_logic_vector(2 downto 0);
        ArBurst : in    std_logic_vector(1 downto 0);
        ArValid : in    std_logic;
        ArReady : out   std_logic;
        RData   : out   std_logic_vector(DataWidth_g - 1 downto 0);
        RResp   : out   std_logic_vector(1 downto 0);
        RLast   : out   std_logic;
        RValid  : out   std_logic;
        RReady  : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of omap_tb_axi_ram is

    constant Bytes_c : positive := DataWidth_g / 8;
    constant Queue_c : positive := 16;

    type AddrQueue_t is array (0 to Queue_c - 1) of natural;
    type LenQueue_t is array (0 to Queue_c - 1) of natural range 0 to 255;
    type RespQueue_t is array (0 to Queue_c - 1) of std_logic_vector(1 downto 0);

    signal AwReady_i : std_logic := '0';
    signal WReady_i  : std_logic := '0';
    signal ArReady_i : std_logic := '0';
    signal RValid_i  : std_logic := '0';
    signal BValid_i  : std_logic := '0';

begin

    AwReady <= AwReady_i;
    WReady  <= WReady_i;
    ArReady <= ArReady_i;
    RValid  <= RValid_i;
    BValid  <= BValid_i;

    -- Write channels: AW queue, W beats of the oldest command, B queue
    p_write : process (Clk) is
        variable AwQ_v    : AddrQueue_t;
        variable AwL_v    : LenQueue_t;
        variable AwHead_v : natural  := 0;
        variable AwCnt_v  : natural  := 0;
        variable Beat_v   : natural  := 0;
        variable Err_v    : boolean  := false;
        variable BQ_v     : RespQueue_t;
        variable BHead_v  : natural  := 0;
        variable BCnt_v   : natural  := 0;
        variable Seed1_v  : positive := 11 + Index_g;
        variable Seed2_v  : positive := 23;
        variable Rnd_v    : real;
        variable Base_v   : natural;
        variable A_v      : natural;

        impure function stall return boolean is
        begin
            uniform(Seed1_v, Seed2_v, Rnd_v);
            return Rnd_v * 100.0 < real(Mem_v.getStall(Index_g));
        end function;

    -- Comment for the style checker: functions above, statements below
    begin
        if rising_edge(Clk) then
            -- AW handshake
            if AwValid = '1' and AwReady_i = '1' then
                AwQ_v((AwHead_v + AwCnt_v) mod Queue_c) := to_integer(unsigned(AwAddr(minimum(AddrWidth_g, 30) - 1 downto 0)));
                AwL_v((AwHead_v + AwCnt_v) mod Queue_c) := to_integer(unsigned(AwLen));
                assert AwBurst = "01"
                    report "omap_tb_axi_ram: only INCR bursts are supported"
                    severity error;
                assert to_integer(unsigned(AwSize)) = integer(log2(real(Bytes_c)))
                    report "omap_tb_axi_ram: only full-width beats are supported"
                    severity error;
                AwCnt_v                                 := AwCnt_v + 1;
            end if;

            -- W handshake: bytes of the beat at the aligned address of the command plus the beat offset
            if WValid = '1' and WReady_i = '1' then
                Base_v := (AwQ_v(AwHead_v) / Bytes_c) * Bytes_c + Beat_v * Bytes_c;

                for i in 0 to Bytes_c - 1 loop
                    if WStrb(i) = '1' then
                        A_v := Base_v + i;
                        if Mem_v.isWriteError(Index_g, A_v) then
                            Err_v := true;
                        else
                            Mem_v.write8(Index_g, A_v, WData(8 * i + 7 downto 8 * i));
                            Mem_v.noteWrite(Index_g, A_v);
                        end if;
                    end if;
                end loop;

                if Beat_v = AwL_v(AwHead_v) then
                    assert WLast = '1'
                        report "omap_tb_axi_ram: WLast missing on the last beat"
                        severity error;
                    if Err_v then
                        BQ_v((BHead_v + BCnt_v) mod Queue_c) := "10";
                    else
                        BQ_v((BHead_v + BCnt_v) mod Queue_c) := "00";
                    end if;
                    BCnt_v   := BCnt_v + 1;
                    Err_v    := false;
                    Beat_v   := 0;
                    AwHead_v := (AwHead_v + 1) mod Queue_c;
                    AwCnt_v  := AwCnt_v - 1;
                else
                    assert WLast = '0'
                        report "omap_tb_axi_ram: WLast before the last beat"
                        severity error;
                    Beat_v := Beat_v + 1;
                end if;
            end if;

            -- B handshake
            if BValid_i = '1' and BReady = '1' then
                BHead_v := (BHead_v + 1) mod Queue_c;
                BCnt_v  := BCnt_v - 1;
            end if;

            AwReady_i <= '1' when AwCnt_v < Queue_c - 1 and not stall else '0';
            WReady_i  <= '1' when AwCnt_v > 0 and not stall else '0';
            if BCnt_v > 0 then
                BResp    <= BQ_v(BHead_v);
                BValid_i <= '1';
            else
                BResp    <= "00";
                BValid_i <= '0';
            end if;

            if Rst = '1' then
                AwHead_v  := 0;
                AwCnt_v   := 0;
                Beat_v    := 0;
                Err_v     := false;
                BHead_v   := 0;
                BCnt_v    := 0;
                AwReady_i <= '0';
                WReady_i  <= '0';
                BValid_i  <= '0';
            end if;
        end if;
    end process;

    -- Read channels: AR queue, R beats of the oldest command
    p_read : process (Clk) is
        variable ArQ_v    : AddrQueue_t;
        variable ArL_v    : LenQueue_t;
        variable ArHead_v : natural  := 0;
        variable ArCnt_v  : natural  := 0;
        variable Beat_v   : natural  := 0;
        variable Seed1_v  : positive := 37 + Index_g;
        variable Seed2_v  : positive := 41;
        variable Rnd_v    : real;
        variable Base_v   : natural;
        variable Err_v    : boolean;

        impure function stall return boolean is
        begin
            uniform(Seed1_v, Seed2_v, Rnd_v);
            return Rnd_v * 100.0 < real(Mem_v.getStall(Index_g));
        end function;

    -- Comment for the style checker: functions above, statements below
    begin
        if rising_edge(Clk) then
            if ArValid = '1' and ArReady_i = '1' then
                ArQ_v((ArHead_v + ArCnt_v) mod Queue_c) := to_integer(unsigned(ArAddr(minimum(AddrWidth_g, 30) - 1 downto 0)));
                ArL_v((ArHead_v + ArCnt_v) mod Queue_c) := to_integer(unsigned(ArLen));
                assert ArBurst = "01"
                    report "omap_tb_axi_ram: only INCR bursts are supported"
                    severity error;
                assert to_integer(unsigned(ArSize)) = integer(log2(real(Bytes_c)))
                    report "omap_tb_axi_ram: only full-width beats are supported"
                    severity error;
                ArCnt_v                                 := ArCnt_v + 1;
            end if;

            -- Beat taken
            if RValid_i = '1' and RReady = '1' then
                Mem_v.noteRead(Index_g);
                if Beat_v = ArL_v(ArHead_v) then
                    Beat_v   := 0;
                    ArHead_v := (ArHead_v + 1) mod Queue_c;
                    ArCnt_v  := ArCnt_v - 1;
                else
                    Beat_v := Beat_v + 1;
                end if;
            end if;

            ArReady_i <= '1' when ArCnt_v < Queue_c - 1 and not stall else '0';

            -- Next beat (a presented beat stays until it is taken)
            if ArCnt_v > 0 and (RValid_i = '0' or RReady = '1') then
                if stall then
                    RValid_i <= '0';
                else
                    Base_v := (ArQ_v(ArHead_v) / Bytes_c) * Bytes_c + Beat_v * Bytes_c;
                    Err_v  := false;

                    for i in 0 to Bytes_c - 1 loop
                        RData(8 * i + 7 downto 8 * i) <= Mem_v.read8(Index_g, Base_v + i);
                        if Mem_v.isReadError(Index_g, Base_v + i) then
                            Err_v := true;
                        end if;
                    end loop;

                    RResp    <= "10" when Err_v else "00";
                    RLast    <= '1' when Beat_v = ArL_v(ArHead_v) else '0';
                    RValid_i <= '1';
                end if;
            elsif ArCnt_v = 0 and RReady = '1' then
                RValid_i <= '0';
            end if;

            if Rst = '1' then
                ArHead_v  := 0;
                ArCnt_v   := 0;
                Beat_v    := 0;
                ArReady_i <= '0';
                RValid_i  <= '0';
            end if;
        end if;
    end process;

end architecture;
