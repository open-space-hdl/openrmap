---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types and constants of the core testbench: VVC instances, control of the packet network model and
-- observations of the two cores.
--
-- Documentation: hdl/omap_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.omap_initiator_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package omap_core_tb_pkg is

    -- Cores: 0 (A) and 1 (B); network directions: 0 from A to B, 1 from B to A

    -- AXI4-Stream VVC instances (core or direction added)
    constant VvcCoReqData_c : natural := 0; -- Master: write data of the Initiator requests
    constant VvcCoRepData_c : natural := 2; -- Slave: reply data of the Initiator
    constant VvcCoUsrTx_c   : natural := 4; -- Master: packets to the user port
    constant VvcCoUsrRx_c   : natural := 6; -- Slave: packets from the user port
    constant VvcCoCap_c     : natural := 8; -- Slave: packets captured in the network

    -- Network faults, applied in the link mode to every packet while set
    constant FaultNone_c     : natural := 0;
    constant FaultFlip_c     : natural := 1; -- Bit 4 of data character Idx inverted
    constant FaultTruncate_c : natural := 2; -- EEP instead of data character Idx, rest of the packet dropped
    constant FaultDrop_c     : natural := 3; -- Packet dropped

    type NetCtrl_t is record
        Capture : std_logic; -- '1': packets of the source core go to the capture VVC, not to the other core
        Fault   : natural;
        Idx     : natural;
    end record;

    constant NetCtrlInit_c : NetCtrl_t := (
        Capture => '0',
        Fault   => FaultNone_c,
        Idx     => 0
    );

    type NetCtrlArray_t is array (0 to 1) of NetCtrl_t;

    type IniReqArray_t is array (0 to 1) of IniReq_t;

    type CoreObs_t is record
        ReqReady  : std_logic;
        ConfCnt   : natural;
        Conf      : IniConfArray_t;
        IndCnt    : natural;
        IndStatus : std_logic_vector(7 downto 0);
        Irq       : std_logic;
    end record;

    type CoreObsArray_t is array (0 to 1) of CoreObs_t;

    -- Logical addresses of the cores
    type ByteArray2_t is array (0 to 1) of std_logic_vector(7 downto 0);

    constant CoreLa_c : ByteArray2_t := (x"20", x"30");

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body omap_core_tb_pkg is

end package body;
