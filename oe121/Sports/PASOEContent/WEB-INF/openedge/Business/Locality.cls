/*------------------------------------------------------------------------
    File        : Locality
    Purpose     : Simple class for locality data
    Author(s)   : Dustin Grau (dugrau@progress.com)
    Created     : 06/02/15
    Notes       :
  ----------------------------------------------------------------------*/

@program FILE(name="Locality.cls", module="AppServer").
@openapi.openedge.export FILE(type="REST", executionMode="singleton", useReturnValue="false", writeDataSetBeforeImage="false").
@progress.service.resource FILE(name="locality", URI="/locality", schemaName="", schemaFile="").

using Progress.Lang.* from propath.
using OpenEdge.Core.Collections.* from propath.

block-level on error undo, throw.

{Common/config.i}

class Business.Locality inherits Spark.Core.Service.SparkEntity use-widget-pool:

    {Common/state.i}

    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/stateProvince", alias="stateProvince", mediaType="application/json").
    method public void getStateProvince ( input  country as character,
                                          output table for states ):
        if (country gt "") ne true then assign country = "usa".

        case country:
            when "can" or
            when "canada" then
                this-object:getProvinces(output table states by-reference).
            when "us" or
            when "usa" then
                this-object:getStates(output table states by-reference).
        end case.
    end method. /* getStateProvince */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/provinces", alias="provinces", mediaType="application/json").
    method public void getProvinces ( output table for states ):
        define variable oMap  as StringStringMap no-undo.
        define variable oIter as IIterator       no-undo.
        define variable oPair as IMapEntry       no-undo.

        empty temp-table states.

        assign oMap = new StringStringMap().

        oMap:Put("AB", "Alberta").
        oMap:Put("BC", "British Columbia").
        oMap:Put("MB", "Manitoba").
        oMap:Put("NB", "New Brunswick").
        oMap:Put("NL", "Newfoundland").
        oMap:Put("NS", "Nova Scotia").
        oMap:Put("NT", "Northwest Territories").
        oMap:Put("NU", "Nunavut").
        oMap:Put("ON", "Ontario").
        oMap:Put("PE", "Prince Edward Island").
        oMap:Put("QC", "Quebec").
        oMap:Put("SK", "Saskatchewan").
        oMap:Put("YT", "Yukon").

        assign oIter = oMap:EntrySet:Iterator().
        do while oIter:HasNext():
            assign oPair = cast(oIter:Next(), IMapEntry).

            create states.
            assign
                states.Abbrev   = string(oPair:key)
                states.FullName = string(oPair:value)
                .
            release states no-error.
        end. /* do while */

        finally:
            delete object oMap no-error.
            delete object oIter no-error.
            delete object oPair no-error.
        end finally.
    end method. /* getProvinces */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/states", alias="states", mediaType="application/json").
    method public void getStates ( output table for states ):
        empty temp-table states.

        for each state no-lock:
            create states.
            assign
                states.Abbrev   = state.State
                states.FullName = state.StateName
                .
            release states no-error.
        end. /* for each */
    end method. /* getStates */

end class.