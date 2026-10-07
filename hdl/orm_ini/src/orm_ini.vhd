---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- RMAP initiator (IN-1 to IN-3): encodes write, read and read-modify-write commands from request
-- descriptors and a data stream, decodes the replies and returns confirmations and the reply data.
-- With Transactions_g > 0 a transaction table associates the replies with the outstanding commands,
-- rejects requests with a Transaction Identifier in use and confirms commands whose reply does not
-- arrive within the timeout.
--
-- Documentation: hdl/orm_ini/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.orm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_ini is
    generic (
        TgtAddrBytes_g : natural range 0 to 16 := 8;
        Transactions_g : natural range 0 to 64 := 8
    );
    port (
        Clk                : in    std_logic;
        Rst                : in    std_logic;
        -- Configuration of the reply timeout
        Cfg_TickCycles     : in    std_logic_vector(15 downto 0);
        Cfg_Timeout        : in    std_logic_vector(15 downto 0);
        -- Requests
        S_Req_Valid        : in    std_logic;
        S_Req_Ready        : out   std_logic;
        S_Req_Code         : in    std_logic_vector(3 downto 0);
        S_Req_TgtAddr      : in    std_logic_vector(maximum(TgtAddrBytes_g, 1) * 8 - 1 downto 0);
        S_Req_TgtAddrLen   : in    std_logic_vector(4 downto 0);
        S_Req_Tla          : in    std_logic_vector(7 downto 0);
        S_Req_Key          : in    std_logic_vector(7 downto 0);
        S_Req_ReplyAddr    : in    std_logic_vector(ReplyAddrMax_c * 8 - 1 downto 0);
        S_Req_ReplyAddrLen : in    std_logic_vector(3 downto 0);
        S_Req_Ila          : in    std_logic_vector(7 downto 0);
        S_Req_Tid          : in    std_logic_vector(15 downto 0);
        S_Req_Addr         : in    std_logic_vector(39 downto 0);
        S_Req_Len          : in    std_logic_vector(23 downto 0);
        -- Data of write and read-modify-write requests
        S_Data_TData       : in    std_logic_vector(7 downto 0);
        S_Data_TValid      : in    std_logic;
        S_Data_TReady      : out   std_logic;
        -- Confirmations
        M_Conf_Valid       : out   std_logic;
        M_Conf_Ready       : in    std_logic;
        M_Conf_Tid         : out   std_logic_vector(15 downto 0);
        M_Conf_Instr       : out   std_logic_vector(7 downto 0);
        M_Conf_Status      : out   std_logic_vector(7 downto 0);
        M_Conf_Len         : out   std_logic_vector(23 downto 0);
        M_Conf_Error       : out   std_logic_vector(1 downto 0); -- 0 none, 1 data error, 2 timeout, 3 TID in use
        -- Reply data
        M_Data_TData       : out   std_logic_vector(7 downto 0);
        M_Data_TLast       : out   std_logic;
        M_Data_TValid      : out   std_logic;
        M_Data_TReady      : in    std_logic;
        -- Commands (N-Char stream)
        M_Cmd_TData        : out   std_logic_vector(7 downto 0);
        M_Cmd_TLast        : out   std_logic;
        M_Cmd_TValid       : out   std_logic;
        M_Cmd_TReady       : in    std_logic;
        -- Replies (N-Char stream)
        S_Rep_TData        : in    std_logic_vector(7 downto 0);
        S_Rep_TLast        : in    std_logic;
        S_Rep_TValid       : in    std_logic;
        S_Rep_TReady       : out   std_logic;
        -- Events (one cycle) and status
        Evt_CmdSent        : out   std_logic;
        Evt_RepOk          : out   std_logic;
        Evt_HdrErr         : out   std_logic;
        Evt_DataErr        : out   std_logic;
        Evt_Unexpected     : out   std_logic;
        Evt_Timeout        : out   std_logic;
        Evt_TidBusy        : out   std_logic;
        Stat_Open          : out   std_logic_vector(7 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of orm_ini is

    constant ErrNone_c    : std_logic_vector(1 downto 0) := "00";
    constant ErrData_c    : std_logic_vector(1 downto 0) := "01";
    constant ErrTimeout_c : std_logic_vector(1 downto 0) := "10";
    constant ErrTidBusy_c : std_logic_vector(1 downto 0) := "11";

    signal RegValid  : std_logic;
    signal RegInstr  : std_logic_vector(7 downto 0);
    signal RegTid    : std_logic_vector(15 downto 0);
    signal RegReady  : std_logic;
    signal RegBusy   : std_logic;
    signal RejValid  : std_logic;
    signal RejReady  : std_logic;
    signal RejTid    : std_logic_vector(15 downto 0);
    signal RejInstr  : std_logic_vector(7 downto 0);
    signal LkTid     : std_logic_vector(15 downto 0);
    signal LkHit     : std_logic;
    signal LkInstr   : std_logic_vector(7 downto 0);
    signal RmValid   : std_logic;
    signal RmTid     : std_logic_vector(15 downto 0);
    signal ToValid   : std_logic;
    signal ToReady   : std_logic;
    signal ToTid     : std_logic_vector(15 downto 0);
    signal ToInstr   : std_logic_vector(7 downto 0);
    signal RxValid   : std_logic;
    signal RxReady   : std_logic;
    signal RxTid     : std_logic_vector(15 downto 0);
    signal RxStatus  : std_logic_vector(7 downto 0);
    signal RxInstr   : std_logic_vector(7 downto 0);
    signal RxLen     : std_logic_vector(23 downto 0);
    signal RxDataErr : std_logic;

    -- Confirmation source locked until its handshake: 0 none, 1 reply, 2 rejection, 3 timeout
    signal Sel     : natural range 0 to 3 := 0;
    signal SelNext : natural range 0 to 3;

begin

    -- IN-1
    i_tx : entity work.orm_ini_tx
        generic map (
            TgtAddrBytes_g => TgtAddrBytes_g
        )
        port map (
            Clk              => Clk,
            Rst              => Rst,
            Req_Valid        => S_Req_Valid,
            Req_Ready        => S_Req_Ready,
            Req_Code         => S_Req_Code,
            Req_TgtAddr      => S_Req_TgtAddr,
            Req_TgtAddrLen   => S_Req_TgtAddrLen,
            Req_Tla          => S_Req_Tla,
            Req_Key          => S_Req_Key,
            Req_ReplyAddr    => S_Req_ReplyAddr,
            Req_ReplyAddrLen => S_Req_ReplyAddrLen,
            Req_Ila          => S_Req_Ila,
            Req_Tid          => S_Req_Tid,
            Req_Addr         => S_Req_Addr,
            Req_Len          => S_Req_Len,
            Data_Valid       => S_Data_TValid,
            Data_Ready       => S_Data_TReady,
            Data_Byte        => S_Data_TData,
            Reg_Valid        => RegValid,
            Reg_Instr        => RegInstr,
            Reg_Tid          => RegTid,
            Reg_Ready        => RegReady,
            Reg_Busy         => RegBusy,
            Rej_Valid        => RejValid,
            Rej_Ready        => RejReady,
            Rej_Tid          => RejTid,
            Rej_Instr        => RejInstr,
            Out_Data         => M_Cmd_TData,
            Out_Last         => M_Cmd_TLast,
            Out_Valid        => M_Cmd_TValid,
            Out_Ready        => M_Cmd_TReady,
            Evt_Sent         => Evt_CmdSent
        );

    -- IN-2
    i_rx : entity work.orm_ini_rx
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Data        => S_Rep_TData,
            In_Last        => S_Rep_TLast,
            In_Valid       => S_Rep_TValid,
            In_Ready       => S_Rep_TReady,
            Lk_Tid         => LkTid,
            Lk_Hit         => LkHit,
            Lk_Instr       => LkInstr,
            Rm_Valid       => RmValid,
            Rm_Tid         => RmTid,
            Conf_Valid     => RxValid,
            Conf_Ready     => RxReady,
            Conf_Tid       => RxTid,
            Conf_Status    => RxStatus,
            Conf_Instr     => RxInstr,
            Conf_Len       => RxLen,
            Conf_DataErr   => RxDataErr,
            Out_Data       => M_Data_TData,
            Out_Last       => M_Data_TLast,
            Out_Valid      => M_Data_TValid,
            Out_Ready      => M_Data_TReady,
            Evt_HdrErr     => Evt_HdrErr,
            Evt_Unexpected => Evt_Unexpected,
            Evt_DataErr    => Evt_DataErr,
            Evt_Rx         => Evt_RepOk
        );

    -- IN-3
    g_table : if Transactions_g > 0 generate

        i_tt : entity work.orm_ini_tt
            generic map (
                Transactions_g => Transactions_g
            )
            port map (
                Clk            => Clk,
                Rst            => Rst,
                Cfg_TickCycles => Cfg_TickCycles,
                Cfg_Timeout    => Cfg_Timeout,
                Reg_Valid      => RegValid,
                Reg_Tid        => RegTid,
                Reg_Instr      => RegInstr,
                Reg_Ready      => RegReady,
                Reg_Busy       => RegBusy,
                Lk_Tid         => LkTid,
                Lk_Hit         => LkHit,
                Lk_Instr       => LkInstr,
                Rm_Valid       => RmValid,
                Rm_Tid         => RmTid,
                To_Valid       => ToValid,
                To_Ready       => ToReady,
                To_Tid         => ToTid,
                To_Instr       => ToInstr,
                Stat_Open      => Stat_Open
            );

    end generate;

    g_notable : if Transactions_g = 0 generate
        -- Every reply is passed on; no duplicate check, no timeout
        RegReady  <= '1';
        RegBusy   <= '0';
        LkHit     <= '1';
        LkInstr   <= RxInstr;
        ToValid   <= '0';
        ToTid     <= (others => '0');
        ToInstr   <= (others => '0');
        Stat_Open <= (others => '0');
    end generate;

    -- Confirmations: reply before rejection before timeout, each source kept until its handshake
    p_sel : process (all) is
    begin
        SelNext <= Sel;
        if Sel = 0 or M_Conf_Ready = '1' then
            if RxValid = '1' and not (Sel = 1 and M_Conf_Ready = '1') then
                SelNext <= 1;
            elsif RejValid = '1' and not (Sel = 2 and M_Conf_Ready = '1') then
                SelNext <= 2;
            elsif ToValid = '1' and not (Sel = 3 and M_Conf_Ready = '1') then
                SelNext <= 3;
            else
                SelNext <= 0;
            end if;
        end if;
    end process;

    p_selreg : process (Clk) is
    begin
        if rising_edge(Clk) then
            Sel <= SelNext;
            if Rst = '1' then
                Sel <= 0;
            end if;
        end if;
    end process;

    M_Conf_Valid  <= RxValid when Sel = 1 else
                     RejValid when Sel = 2 else
                     ToValid when Sel = 3 else
                     '0';
    RxReady       <= M_Conf_Ready when Sel = 1 else '0';
    RejReady      <= M_Conf_Ready when Sel = 2 else '0';
    ToReady       <= M_Conf_Ready when Sel = 3 else '0';
    M_Conf_Tid    <= RxTid when Sel = 1 else
                     RejTid when Sel = 2 else
                     ToTid;
    M_Conf_Instr  <= RxInstr when Sel = 1 else
                     RejInstr when Sel = 2 else
                     ToInstr;
    M_Conf_Status <= RxStatus when Sel = 1 else x"00";
    M_Conf_Len    <= RxLen when Sel = 1 else (others => '0');
    M_Conf_Error  <= ErrData_c when Sel = 1 and RxDataErr = '1' else
                     ErrNone_c when Sel = 1 else
                     ErrTidBusy_c when Sel = 2 else
                     ErrTimeout_c;
    Evt_Timeout   <= ToValid and M_Conf_Ready when Sel = 3 else '0';
    Evt_TidBusy   <= RejValid and M_Conf_Ready when Sel = 2 else '0';

end architecture;
