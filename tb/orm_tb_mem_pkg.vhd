---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Memory of the AXI memory model orm_tb_axi_ram: a protected type with one byte array per model
-- instance, error ranges for read and write accesses, the backpressure setting and access
-- statistics. The object itself is the shared variable Mem_v of orm_tb_memvar_pkg.
--
-- Documentation: hdl/orm_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package orm_tb_mem_pkg is

    constant TbMemInstances_c : positive := 4;
    constant TbMemBytes_c     : positive := 65536; -- Addresses wrap at this size

    type TbMem_t is protected

        -- Backdoor access (addresses modulo TbMemBytes_c)
        procedure write8 (
            idx  : natural;
            addr : natural;
            data : std_logic_vector(7 downto 0));

        impure function read8 (
            idx  : natural;
            addr : natural) return std_logic_vector;

        -- Fills n bytes from addr with (seed + i) mod 256
        procedure fill (
            idx  : natural;
            addr : natural;
            n    : natural;
            seed : natural);

        -- Error responses (SLVERR) for accesses to bytes from first to last; first > last disables
        procedure setReadError (
            idx   : natural;
            first : natural;
            last  : natural);

        procedure setWriteError (
            idx   : natural;
            first : natural;
            last  : natural);

        impure function isReadError (
            idx  : natural;
            addr : natural) return boolean;

        impure function isWriteError (
            idx  : natural;
            addr : natural) return boolean;

        -- Percentage of cycles in which the model holds its ready and valid signals low (0 to 90)
        procedure setStall (
            idx     : natural;
            percent : natural);

        impure function getStall (idx : natural) return natural;

        -- Statistics: bytes written (strobed), lowest and highest address written, read beats
        procedure clearStats (idx : natural);

        procedure noteWrite (
            idx  : natural;
            addr : natural);

        procedure noteRead (idx : natural);

        impure function bytesWritten (idx : natural) return natural;

        impure function lowestWritten (idx : natural) return natural;

        impure function highestWritten (idx : natural) return natural;

        impure function beatsRead (idx : natural) return natural;

    end protected;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body orm_tb_mem_pkg is

    type TbMem_t is protected body

        type ByteArray_t is array (0 to TbMemBytes_c - 1) of std_logic_vector(7 downto 0);
        type ByteArrayPtr_t is access ByteArray_t;
        type PtrArray_t is array (0 to TbMemInstances_c - 1) of ByteArrayPtr_t;
        type NatArray_t is array (0 to TbMemInstances_c - 1) of natural;

        variable Mem_v     : PtrArray_t;
        variable RdFirst_v : NatArray_t := (others => 1);
        variable RdLast_v  : NatArray_t := (others => 0);
        variable WrFirst_v : NatArray_t := (others => 1);
        variable WrLast_v  : NatArray_t := (others => 0);
        variable Stall_v   : NatArray_t := (others => 0);
        variable WrCnt_v   : NatArray_t := (others => 0);
        variable WrLow_v   : NatArray_t := (others => natural'high);
        variable WrHigh_v  : NatArray_t := (others => 0);
        variable RdCnt_v   : NatArray_t := (others => 0);

        procedure allocate (idx : natural) is
        begin
            if Mem_v(idx) = null then
                Mem_v(idx) := new ByteArray_t'(others => x"00");
            end if;
        end procedure;

        procedure write8 (
            idx  : natural;
            addr : natural;
            data : std_logic_vector(7 downto 0)) is
        begin
            allocate(idx);
            Mem_v(idx)(addr mod TbMemBytes_c) := data;
        end procedure;

        impure function read8 (
            idx  : natural;
            addr : natural) return std_logic_vector is
        begin
            allocate(idx);
            return Mem_v(idx)(addr mod TbMemBytes_c);
        end function;

        procedure fill (
            idx  : natural;
            addr : natural;
            n    : natural;
            seed : natural) is
        begin

            for i in 0 to n - 1 loop
                write8(idx, addr + i, std_logic_vector(to_unsigned((seed + i) mod 256, 8)));
            end loop;

        end procedure;

        procedure setReadError (
            idx   : natural;
            first : natural;
            last  : natural) is
        begin
            RdFirst_v(idx) := first;
            RdLast_v(idx)  := last;
        end procedure;

        procedure setWriteError (
            idx   : natural;
            first : natural;
            last  : natural) is
        begin
            WrFirst_v(idx) := first;
            WrLast_v(idx)  := last;
        end procedure;

        impure function isReadError (
            idx  : natural;
            addr : natural) return boolean is
        begin
            return addr >= RdFirst_v(idx) and addr <= RdLast_v(idx);
        end function;

        impure function isWriteError (
            idx  : natural;
            addr : natural) return boolean is
        begin
            return addr >= WrFirst_v(idx) and addr <= WrLast_v(idx);
        end function;

        procedure setStall (
            idx     : natural;
            percent : natural) is
        begin
            Stall_v(idx) := minimum(percent, 90);
        end procedure;

        impure function getStall (idx : natural) return natural is
        begin
            return Stall_v(idx);
        end function;

        procedure clearStats (idx : natural) is
        begin
            WrCnt_v(idx)  := 0;
            WrLow_v(idx)  := natural'high;
            WrHigh_v(idx) := 0;
            RdCnt_v(idx)  := 0;
        end procedure;

        procedure noteWrite (
            idx  : natural;
            addr : natural) is
        begin
            WrCnt_v(idx)  := WrCnt_v(idx) + 1;
            WrLow_v(idx)  := minimum(WrLow_v(idx), addr);
            WrHigh_v(idx) := maximum(WrHigh_v(idx), addr);
        end procedure;

        procedure noteRead (idx : natural) is
        begin
            RdCnt_v(idx) := RdCnt_v(idx) + 1;
        end procedure;

        impure function bytesWritten (idx : natural) return natural is
        begin
            return WrCnt_v(idx);
        end function;

        impure function lowestWritten (idx : natural) return natural is
        begin
            return WrLow_v(idx);
        end function;

        impure function highestWritten (idx : natural) return natural is
        begin
            return WrHigh_v(idx);
        end function;

        impure function beatsRead (idx : natural) return natural is
        begin
            return RdCnt_v(idx);
        end function;

    end protected body;

end package body;
