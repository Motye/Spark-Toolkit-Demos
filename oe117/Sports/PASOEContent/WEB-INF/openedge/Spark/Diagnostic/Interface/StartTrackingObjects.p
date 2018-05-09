/*------------------------------------------------------------------------
    File        : StartTrackingObjects.p
    Purpose     : 
    Description : 
    Author(s)   : Dustin Grau
    Created     : Wed May 09 13:08:50 EDT 2018
    Notes       :
  ----------------------------------------------------------------------*/

/* ***************************  Definitions  ************************** */

block-level on error undo, throw.

define input parameter piAgentID   as integer   no-undo.
define input parameter pcProcedure as character no-undo.

/* ***************************  Main Block  *************************** */

message "StartTrackingObjects:" piAgentID.

Spark.Diagnostic.Util.OEMetrics:Instance:StartTrackingObjects(piAgentID, pcProcedure).