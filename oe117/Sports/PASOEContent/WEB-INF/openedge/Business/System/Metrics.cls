/*------------------------------------------------------------------------
    File        : Metrics
    Purpose     : 
    Syntax      : 
    Description : 
    Author(s)   : Dustin Grau
    Created     : Wed Apr 25 14:37:55 EDT 2018
    Notes       : 
  ----------------------------------------------------------------------*/

@program FILE(name="Metrics.cls", module="AppServer").
@openapi.openedge.export FILE(type="REST", executionMode="singleton", useReturnValue="false", writeDataSetBeforeImage="false").
@progress.service.resource FILE(name="metrics", URI="/metrics", schemaName="", schemaFile="").

using Progress.Lang.* from propath.
using Spark.Core.Util.OEMetrics from propath.

block-level on error undo, throw.

class Business.System.Metrics: 

    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="invoke", URI="/objects", alias="objects", mediaType="application/json").
    method public void getObjects ( ):
        define variable oMetrics as OEMetrics no-undo.
        assign oMetrics = new OEMetrics().
        oMetrics:getABLObjectsReport().
    end method. /* getObjects */

end class.