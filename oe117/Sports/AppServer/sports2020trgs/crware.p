/***************************************************************************\
*****************************************************************************
**
**     Program: crware.p
**    Descript:
**
*****************************************************************************
\***************************************************************************/

trigger procedure for create of Warehouse.

assign Warehouse.WarehouseNum = next-value(NextWareNum).
