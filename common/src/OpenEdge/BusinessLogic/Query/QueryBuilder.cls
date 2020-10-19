/* *************************************************************************************************************************
Copyright (c) 2019-2020 by Progress Software Corporation and/or one of its subsidiaries or affiliates. All rights reserved.
************************************************************************************************************************** */
/*------------------------------------------------------------------------
    File        : QueryBuilder
    Purpose     :
    Syntax      :
    Description :
    Author(s)   : pjudge & dugrau
    Created     : Thu May 10 12:38:00 EDT 2018
    Notes       : ADAS-101
  ----------------------------------------------------------------------*/
block-level on error undo, throw.

using Ccs.BusinessLogic.IGetDataRequest.
using Ccs.BusinessLogic.IGetDataTableRequest.
using Ccs.BusinessLogic.IQueryGroup.
using Ccs.BusinessLogic.IQueryPredicate.
using Ccs.BusinessLogic.JoinEnum.
using Ccs.BusinessLogic.QueryOperatorEnum.
using Ccs.BusinessLogic.SortOrderEnum.
using Ccs.Common.Support.ICharacterArrayHolder.
using Ccs.Common.Support.ICharacterHolder.
using Ccs.Common.Support.IDateArrayHolder.
using Ccs.Common.Support.IDateHolder.
using Ccs.Common.Support.IDateTimeArrayHolder.
using Ccs.Common.Support.IDateTimeHolder.
using Ccs.Common.Support.IDateTimeTzArrayHolder.
using Ccs.Common.Support.IDateTimeTzHolder.
using Ccs.Common.Support.IDecimalArrayHolder.
using Ccs.Common.Support.IDecimalHolder.
using Ccs.Common.Support.IInt64ArrayHolder.
using Ccs.Common.Support.IInt64Holder.
using Ccs.Common.Support.IIntegerArrayHolder.
using Ccs.Common.Support.IIntegerHolder.
using Ccs.Common.Support.ILogicalArrayHolder.
using Ccs.Common.Support.ILogicalHolder.
using Ccs.Common.Support.ILongcharArrayHolder.
using Ccs.Common.Support.ILongcharHolder.
using OpenEdge.Core.StringConstant.

class OpenEdge.BusinessLogic.Query.QueryBuilder:

    /* Returns a table/buffer handle for a given name from an input schema

       @param handle The input schema (dataset, buffer, table)
       @param character The table name. Can be the 'real' name or the serialize-name
       @return handle A buffer handle for the given name. */
    method protected handle GetTableBuffer (input phSchema    as handle,
                                            input pcTableName as character):
        define variable iBuffer as integer no-undo.
        define variable hTable  as handle  no-undo.

        if not valid-handle(phSchema) or phSchema:type ne "dataset" then
            return phSchema. /* Return handle as-is if not a dataset. */

        if (pcTableName gt "") ne true then
            return phSchema:get-buffer-handle(1). /* No table name, just get the top buffer by default. */
        else do:
            /**
             * We need to avoid throwing an error if we request a table that does not exist.
             * This is because we'll check if a valid table buffer exists, or roll on to
             * checking each table in the dataset (in the case of a serialized name).
             */
            assign hTable= phSchema:get-buffer-handle(pcTableName) no-error. /* Must keep this no-error! */
            if valid-handle(hTable) then
                return hTable. /* Return if found by actual table name. */

            /* If still here, search by serialize-name of table. */
            do iBuffer = 1 to phSchema:num-buffers:
                assign hTable = phSchema:get-buffer-handle(iBuffer) no-error.
                /* Check if client-sent table matches serialized name. */
                if valid-handle(hTable) then do:
                    if hTable:serialize-name eq pcTableName then
                        return hTable. /* Found table by serialize-name. */
                    else
                        delete object hTable no-error.
                end. /* valid-handle */
            end. /* iBuffer */
        end. /* Non-Empty TableName */

        return ?. /* No schema, no table name, no table found, just return unknown value. */

        finally:
            delete object hTable no-error.
        end finally.
    end method. /* GetTableBuffer */

    /* Returns a fiueld handle for a given name from an input buffer

       @param handle The input table/buffer
       @param character The field name. Can be the 'real' name or the serialize-name
       @return handle A buffer field handle for the given name. */
    method protected handle GetFieldBuffer (input phTable     as handle,
                                            input pcFieldName as character):
        define variable bhField as handle  no-undo.
        define variable ix      as integer no-undo.

        /* Return the buffer for the field, if it exists in the table. */
        if valid-handle(phTable) then do:
            /**
             * We need to avoid throwing an error if we request a field that does not exist.
             * This is because we'll check if a valid field buffer exists, or roll on to
             * checking each field in the table (in the case of a serialized name).
             */
            assign bhField = phTable:buffer-field(pcFieldName) no-error. /* Must keep this no-error! */
            if valid-handle(bhField) then
                return bhField.

            do ix = 1 to phTable:num-fields:
                assign bhField = phTable:buffer-field(ix) no-error.
                /* Check if client-sent field matches serialized name. */
                if valid-handle(bhField) then do:
                    if bhField:serialize-name eq pcFieldName then
                        return bhField.
                    else
                        delete object bhField no-error.
                end. /* valid-handle */
            end. /* do ix */
        end. /* valid-handle */

        return ?. /* Return unknown value to indicate field is not in the temp-table. */

        finally:
            delete object bhField no-error.
        end finally.
    end method. /* GetFieldBuffer */

    /* Maps a query operator into a string template

       @param QueryOperatorEnum The operator
       @param character The the data type
       @return character A templated operator map of the form "&1 eq &2" */
    method protected character MapOperator (input poOperator as QueryOperatorEnum,
                                            input pcDataType as character ):
        /* http://docs.telerik.com/kendo-ui/api/javascript/data/datasource#configuration-filter.operator */
        define variable cTemplate as character no-undo.

        case poOperator:
            when QueryOperatorEnum:Eq then
                if pcDataType eq "character" then
                    assign cTemplate = '&1 eq "&2"'.
                else
                    assign cTemplate = '&1 eq &2'.
            when QueryOperatorEnum:Ne then
                if pcDataType eq "character" then
                    assign cTemplate = '&1 ne "&2"'.
                else
                    assign cTemplate = '&1 ne &2'.
            when QueryOperatorEnum:Lt then
                assign cTemplate = '&1 lt &2'.
            when QueryOperatorEnum:Le then
                assign cTemplate = '&1 le &2'.
            when QueryOperatorEnum:Gt then
                assign cTemplate = '&1 gt &2'.
            when QueryOperatorEnum:Ge then
                assign cTemplate = '&1 ge &2'.
            when QueryOperatorEnum:Begins then
                assign cTemplate = '&1 begins "&2"'.
            when QueryOperatorEnum:Contains then
                assign cTemplate = '&1 matches "&2"'. /* Value should already be appended/prepended with '*'. */
            when QueryOperatorEnum:Matches then
                assign cTemplate = '&1 matches "&2"'. /* Value should already be appended/prepended with '*'. */
            otherwise
                undo, throw new Progress.Lang.AppError(substitute("Unknown operator '&1' for filter.", poOperator:ToString()), 0).
        end case.

        return cTemplate.
    end method. /* MapOperator */

    /* Creates a templated join phrase for a clause

       @param character The current query string
       @param character The query where clause that's being joined
       @param JoinEnum The join to apply
       @return character A new query string, including the join phrase */
    method protected character MapJoin (input pcQuery  as character,
                                        input pcClause as character,
                                        input poJoinAs as JoinEnum):
        if pcQuery eq "" then
            /* When query string is blank, only provide negations as needed. */
            case poJoinAs:
                when JoinEnum:AndNot or
                when JoinEnum:OrNot or
                when JoinEnum:Not then
                    assign pcQuery = substitute("(not &1)", pcClause).
                otherwise
                    assign pcQuery = substitute("(&1)", pcClause).
            end case.
        else
            /* Otherwise join clause to query as described by join. */
            case poJoinAs:
                when JoinEnum:And then
                    assign pcQuery = substitute("&1 and (&2)", pcQuery, pcClause).
                when JoinEnum:AndNot then
                    assign pcQuery = substitute("&1 and (not &2)", pcQuery, pcClause).
                when JoinEnum:Or then
                    assign pcQuery = substitute("&1 or (&2)", pcQuery, pcClause).
                when JoinEnum:OrNot then
                    assign pcQuery = substitute("&1 or (not &2)", pcQuery, pcClause).
                when JoinEnum:None then
                    assign pcQuery = substitute("(&1)", pcClause). /* No join operator. */
                when JoinEnum:Not then
                    assign pcQuery = substitute("(not &1)", pcClause). /* Negate only. */
            end case.

        return pcQuery.
    end method. /* MapJoin */

    /* Builds a query group string from a group

       @param handle The table/buffer for which the group is being built
       @param QueryGroup The group
       @return character A group string */
    method protected character BuildGroup (input phTable as handle,
                                           input poGroup as IQueryGroup):
        define variable cQueryString as character no-undo initial "".
        define variable cClause      as character no-undo.
        define variable iLoop        as integer   no-undo.
        define variable oJoinAs      as JoinEnum  no-undo.
        define variable cnt as integer no-undo.

        if not valid-object(poGroup) then
            return cQueryString.
        
        /**
         * Note: This is a recursive method, as the provided group may consist of either only
         * query predicates (field, operator, value) or an entire group (nested query). For the
         * case of a group the object will be fed into another call to this method which will
         * result in a nested (bracketed) query clause.
         */
        assign cnt = extent(poGroup:Entries).
        do iLoop = 1 to cnt:
            if type-of(poGroup:Entries[iLoop], IQueryGroup) then
                /* Create a nested query from this child group. */
                assign cClause = this-object:BuildGroup(phTable, cast(poGroup:Entries[iLoop], IQueryGroup))
                       oJoinAs = poGroup:Join /* Use the overall group join. */
                       .
            else
            do:
                /* Create a simple clause frmo the given predicate. */
                assign cClause = this-object:BuildClause(phTable, cast(poGroup:Entries[iLoop], IQueryPredicate))
                       oJoinAs = cast(poGroup:Entries[iLoop], IQueryPredicate):Join
                       .
                // use the group join if the predicate has none
                if not valid-object(oJoinAs) then
                    assign oJoinAs = poGroup:Join.
            end.
            
            // default to an AND join if there's none provided
            if not valid-object(oJoinAs) then
                assign oJoinAs = JoinEnum:And.
            
            /* Continue with joining the clause (single or nested) to the query if non-blank. */
            if not cClause eq '':u then
                assign cQueryString = this-object:MapJoin(cQueryString, cClause, oJoinAs).
        end. /* Looping Entries */

        return cQueryString.
    end method. /* BuildGroup */

    /* Builds a WHERE clause for a table from a QueryPredicate

       @param handle The table buffer handle
       @param QueryPredicate The abstract query predicate
       @return character A string representation of the where clause */
    method protected character BuildClause (input phTable  as handle,
                                            input poClause as IQueryPredicate):
        define variable hField  as handle     no-undo.
        define variable cClause as character  no-undo.
        define variable cField  as character  no-undo.
        define variable cOper   as character  no-undo.
        define variable cType   as character  no-undo.

        /**
         * This should be the raw (public) field as provided by the front-end and must be mapped to a
         * valid internal temp-table field. This may be a serialized name, though the resulting field
         * buffer should be used to extract the real field name. Additionally, it may be impossible to
         * determine the correct datatype without assistance from the field buffer, so that too will be
         * used to convert the value appropriately for the resulting query phrase.
         */
        assign hField = this-object:GetFieldBuffer(phTable, poClause:FieldName) no-error.

        if valid-handle(hField) then
            assign
                cField = hField:name
                cType  = hField:data-type
                .
        else
        do:
            assign cField = poClause:FieldName.

            /**
             * Note: There is no expectation that JSON data will map to RowID, Memptr,
             * or Handle datatypes so those are omitted from detection. Additionally,
             * use of the Values property for extent (array) values is not yet
             * supported due to lack of use-cases.
             */

            case true:
                when not valid-object(poClause:Value) and
                     not valid-object(poClause:Values) then
                    assign cType = "character".

                when type-of(poClause:Value, ILongcharHolder) or
                when type-of(poClause:Value, ILongcharArrayHolder) or
                when type-of(poClause:Value, ICharacterHolder) or
                when type-of(poClause:Value, ICharacterArrayHolder) then
                    assign cType = "character".

                when type-of(poClause:Value, IDateHolder) or
                when type-of(poClause:Value, IDateArrayHolder) then
                    assign cType = "date".

                when type-of(poClause:Value, IDateTimeHolder) or
                when type-of(poClause:Value, IDateTimeArrayHolder) then
                    assign cType = "datetime".

                when type-of(poClause:Value, IDateTimeTzHolder) or
                when type-of(poClause:Value, IDateTimeTzArrayHolder) then
                    assign cType = "datetime-tz".

                when type-of(poClause:Value, IDecimalHolder) or
                when type-of(poClause:Value, IDecimalArrayHolder) then
                    assign cType = "decimal".

                when type-of(poClause:Value, IInt64Holder) or
                when type-of(poClause:Value, IInt64arrayHolder) or
                when type-of(poClause:Value, IIntegerHolder) or
                when type-of(poClause:Value, IIntegerArrayHolder) then
                    assign cType = "integer".

                when type-of(poClause:Value, ILogicalHolder) or
                when type-of(poClause:Value, ILogicalArrayHolder) then
                    assign cType = "logical".

                otherwise
                    assign cType = "character".
            end case.
        end.

        /**
         * Based on the datatype, convert the value and obtain a valid operation string for the clause.
         * The string contains the replacement operators for a "substitute" using the field name and value.
         */
        case cType:
            when "character" then do:
                /* Assumes the Value should only be of Longchar/Character type. */
                if type-of(poClause:Value, ILongcharHolder) or type-of(poClause:Value, ICharacterHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, poClause:Value:ToString()).
            end. /* character */

            when "date" then do:
                if type-of(poClause:Value, ILongcharHolder) or type-of(poClause:Value, ICharacterHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, date(poClause:Value:ToString())).
                else if type-of(poClause:Value, IDateHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, poClause:Value).
            end. /* date */

            when "datetime" then do:
                if type-of(poClause:Value, ILongcharHolder) or type-of(poClause:Value, ICharacterHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, datetime(poClause:Value:ToString())).
                else if type-of(poClause:Value, IDateTimeHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, poClause:Value).
            end. /* datetime */

            when "datetime-tz" then do:
                if type-of(poClause:Value, ILongcharHolder) or type-of(poClause:Value, ICharacterHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, datetime-tz(poClause:Value:ToString())).
                else if type-of(poClause:Value, IDateTimeTzHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, poClause:Value).
            end. /* datetime-tz */

            when "decimal" then do:
                if type-of(poClause:Value, ILongcharHolder) or type-of(poClause:Value, ICharacterHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, decimal(poClause:Value:ToString())).
                else if type-of(poClause:Value, IDecimalHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, poClause:Value).
            end. /* decimal */

            when "integer" then do:
                if type-of(poClause:Value, ILongcharHolder) or type-of(poClause:Value, ICharacterHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, integer(poClause:Value:ToString())).
                else if type-of(poClause:Value, IIntegerHolder) or type-of(poClause:Value, IInt64Holder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, poClause:Value).
            end. /* integer */

            when "logical" then do:
                if type-of(poClause:Value, ILongcharHolder) or type-of(poClause:Value, ICharacterHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, logical(poClause:Value:ToString())).
                else if type-of(poClause:Value, ILogicalHolder) then
                    assign cClause = substitute(this-object:MapOperator(poClause:Operator, cType),
                                                cField, poClause:Value).
            end. /* logical */
        end case.

        return cClause.

        catch err as Progress.Lang.Error:
            return "". /* Return empty clause if an error is encountered. */
        end catch.
    end method. /* BuildClause */

    /***** End Protected / Begin Public *****/

    /* Builds a query handle (object) from a IGetDataRequest object. This method maps
       the input names to the input handle's SERIALIZE-NAMEs and uses the 'real'
       names to build the where clause

       @param IGetDataRequest A valid queryn definition
       @param handle a Dataset or buffer (TT or DB) handle
       @return handle A valid QUERY handle */
    method public handle BuildQuery (input pFilter as IGetDataRequest,
                                     input pSchema as handle):
        define variable hQuery as handle no-undo.

        create query hQuery.
        hQuery:set-buffers(pSchema).
        hQuery:query-prepare(substitute("for each &1 &2", pSchema:name, this-object:BuildQueryString(pFilter, pSchema))).
        hQuery:query-open.

        return hQuery.
    end method. /* BuildQueryString */

    /* Builds a query string from a IGetDataRequest object. This method does
       no name conversions - just takes the names from the input object.

       @param IGetDataRequest A valid queryn definition
       @return character A complete WHERE clause , with no name conversions */
    method public character BuildQueryString (input pFilter as IGetDataRequest):
        /**
         * Call internal method with filter but no schema. However, due to the
         * need to utilize schema for detecting real field names (from public,
         * serialized names) and field datatypes this will likely result in a
         * thrown error. It is far better to call this method directly with a
         * dataset or temp-table handle.
         */
        return BuildQueryString(pFilter, ?).
    end method. /* BuildQueryString */
    
    /* Builds a query string for a single table from a IGetDataTableRequest object.
       
       This method maps the input names to the input handle's SERIALIZE-NAMEs and 
       uses the 'real' names to build the where clause
       
       @param IGetDataTableRequest A valid 
       @param handle a Dataset or buffer (TT or DB) handle
       @param logical TRUE if the FILTER (where) expression must be included, FALSE if not
       @param logical TRUE if the SORT expression must be included , FALSE if not
       @return character A complete WHERE clause */
    method public character BuildQueryString (input pFilter as IGetDataTableRequest,
                                              input pInclFilter as logical,
                                              input pInclSort as logical,
                                              input pSchema as handle):
        define variable hdlFld as handle no-undo.
        define variable loop as integer no-undo.
        define variable cnt as integer no-undo.
        define variable sortOrder as character no-undo.
        define variable qryString as character no-undo.
        define variable queryWhere as character no-undo.
        define variable querySort as character no-undo.
        define variable fieldName as character no-undo.
        
        // we don't want anything, get nothing
        if  pInclFilter eq false
        and pInclSort eq false
        then
            return qryString.
        
        // allow for ?, which defaults to true
        if not pInclFilter eq false then
        do:
            // If the QueryString is set, use it.  
            if  not pFilter:QueryString eq ?
            and not pFilter:QueryString eq '':u
            then
                return pFilter:QueryString.
            else
            do:
                if not valid-object(pFilter:QueryDefinition)
                or not valid-object(pFilter:QueryDefinition:QuerySelection)
                then
                    assign queryWhere = '':u.
                else
                /* Build either a nested query or a simple clause, depending on the object available. */
                if type-of(pFilter:QueryDefinition:QuerySelection, IQueryGroup) then
                    assign queryWhere = this-object:BuildGroup(pSchema, cast(pFilter:QueryDefinition:QuerySelection, IQueryGroup)).
                else
                if type-of(pFilter:QueryDefinition:QuerySelection, IQueryPredicate) then
                    assign queryWhere = this-object:BuildClause(pSchema, cast(pFilter:QueryDefinition:QuerySelection, IQueryPredicate)).
            end.
            
            /* If query string is blank, set to simply "true". */
            if queryWhere eq '':u then
                assign queryWhere = 'true':u.
            
            if not queryWhere eq '':u then
                assign qryString = 'where ':u + left-trim(queryWhere, 'where ':u).
        end.    // include where/filter
        
        // allow for ?, which defaults to true
        if not pInclSort eq false then
        do:
            if valid-object(pFilter:QueryDefinition) then
                assign cnt = extent(pFilter:QueryDefinition:QuerySort).
            
            SORT-LOOP:
            do loop = 1 to cnt:
                if not valid-object(pFilter:QueryDefinition:QuerySort[loop]) then
                    next SORT-LOOP.
                
                /* Create the sort clause based on the real field information. */
                assign hdlFld = this-object:GetFieldBuffer(pSchema, pFilter:QueryDefinition:QuerySort[loop]:FieldName).
                if valid-handle(hdlFld) then
                    assign fieldName = hdlFld:name.
                else
                    assign fieldName = pFilter:QueryDefinition:QuerySort[loop]:FieldName.
                
                if valid-object(pFilter:QueryDefinition:QuerySort[loop]:SortOrder)
                and pFilter:QueryDefinition:QuerySort[loop]:SortOrder eq SortOrderEnum:Descending
                then
                    // make sure there's a space here
                    assign sortOrder = StringConstant:SPACE + 'descending':u.
                else
                    assign sortOrder = '':u.
                
                assign querySort = substitute('&1 by &2&3':u, 
                                              querySort,
                                              fieldName,
                                              sortOrder).
            end. /* do iLoop */
            
            if not querySort eq '':u then
                assign qryString = qryString + StringConstant:SPACE + trim(querySort)
                       // in case there is no WHERE clause
                       qryString = trim(qryString)
                       .
        end.    // include sort
        
        return qryString.
    end method.
    
    /* Builds a query string from a IGetDataRequest object. This method maps
       the input names to the input handle's SERIALIZE-NAMEs and uses the 'real'
       names to build the where clause
       
       @param IGetDataRequest A valid queryn definition
       @param handle a Dataset or buffer (TT or DB) handle
       @return character A complete WHERE clause */
    method public character BuildQueryString (input pFilter as IGetDataRequest,
                                              input pSchema as handle):
        define variable cQueryString as character       no-undo.
        define variable bhTable      as handle          no-undo.
        define variable iLoop       as integer         no-undo.
        define variable cSortBy      as character       no-undo extent.
        define variable tblName as character no-undo.
        define variable tblQry as character no-undo.
        define variable cnt as integer no-undo.
        
        /* Cycle through all the table requests for this filter. */
        assign cnt             = extent(pFilter:TableRequests)
               extent(cSortBy) = cnt
               .
        do iLoop = 1 to cnt:
            if valid-handle(pSchema) and pSchema:type eq "dataset" then
                assign bhTable = this-object:GetTableBuffer(pSchema, pFilter:TableRequests[iLoop]:TableName).
            else if valid-handle(pSchema) and pSchema:type eq "temp-table" then
                assign bhTable = pSchema. /* Use given temp-table handle as-is. */
            
            assign tblQry         = BuildQueryString(pFilter:TableRequests[iLoop], yes, no, bhTable)
                   cSortBy[iLoop] = BuildQueryString(pFilter:TableRequests[iLoop], no, yes, bhTable)
                   .
            /* Remember the real name for each table. */
            if valid-handle(bhTable) then
                assign tblName = bhTable:name.
            else
                assign tblName = '':u.
            
            /* If we have a valid name for an additional table, append the next table query. */
            assign cQueryString = substitute("&1, each &2 &3", cQueryString, tblName, tblQry)
                   /* Trim commas and spaces from query string after each table. */
                   cQueryString = trim(trim(cQueryString, ","))
                   .
        end. /* extent pFilter:TableRequests */
        
        /* Add the sort phrases after all table "where" phrases. */
        do iLoop = 1 to cnt:
            assign cQueryString = substitute("&1 &2", cQueryString, cSortBy[iLoop]).
        end. /* extent cSortBy */
        
        /* Return the first TableRequest's query string by default. */
        return trim(cQueryString).
    end method. /* BuildQueryString */
    
    /* Merges 2 query strings with specified join. The resulting query string has the format
            "WHERE ( <string-1> ) <join> ( <string-2> ) BY <by-1> BY <by-2> "
        or 
            "WHERE TRUE BY <by-1> BY <by-2>"
        if only BY clauses are passed in.
        
        Each input string is put in parentheses, except when 
            i)   the input strings are both ?
            ii)  one or both of the input strings is empty
            iii) there are no where clauses
       
       - Join values
         - if the join is null, use JoinEnum:And
         - if the join is NONE, use JoinEnum:And
         - if the join is NOT, use JoinEnum:AndNot
         - For other values, use as specified
       
       - if both strings are null, then shortcut and return 
                ? and ?     = where true
                ? or ?      = where true
                ? and not ? = where false
                ? or not ?  = where true
       
       - No validation (of field/table names) is done; this is a simple string merge routine.
       - If either string is empty, no join is performed, and the other string
         is returned (even if empty)
       - If either query string containd BY clause(s), these are appended
       
       @param character  The first query string
       @param JoinEnum   The join criteria
       @param character  The second query string
       @return character The merged query string */
    method public character MergeQueryStrings(input pQueryString1 as character,
                                              input pJoin as JoinEnum,
                                              input pQueryString2 as character):
        define variable mergedQry as character no-undo.
        define variable startPos as integer no-undo.
        define variable endPos as integer no-undo.
        define variable byExpr as character no-undo.
        
        // Default Join is AND 
        if not valid-object(pJoin) 
        or pJoin eq JoinEnum:None 
        then
            assign pJoin = JoinEnum:And.
        else
        if pJoin eq JoinEnum:Not then
            assign pJoin = JoinEnum:AndNot.
        
        // If only nulls are passed in, shortcut the join
        if  pQueryString1 eq ? 
        and pQueryString2 eq ?
        then
        do:
            if pJoin eq JoinEnum:AndNot then
                return 'where false':u.
            else
                return 'where true':u.
        end.
        
        if pQueryString1 eq ? then
            assign pQueryString1 = 'where true':u.
        
        if pQueryString2 eq ? then
            assign pQueryString2 = 'where true':u.
        
        // nothing to merge from string2, so return string1
        if pQueryString2 eq '':u then
            return pQueryString1.
        
        // nothing to merge from string1, so return string2
        if pQueryString1 eq '':u then
            return pQueryString2.
        
        // first query
        assign startPos = index(pQueryString1, 'where ':u).
        if not startPos eq 0 then
            assign pQueryString1 = substring(pQueryString1, startPos + 6).
        
        assign startPos = index(pQueryString1, ' by ':u).
        if startPos gt 0 then
            assign byExpr        = byExpr + substring(pQueryString1, startPos)
                   pQueryString1 = trim(substring(pQueryString1, 1, startPos - 1))
                   .
        else
        if pQueryString1 begins 'by ':u then
            assign byExpr        = byExpr + ' ':u + pQueryString1
                   pQueryString1 = '':U
                   .
        
        if not pQueryString1 eq '':u then
            assign pQueryString1 = '( ':u + pQueryString1 + ' )':u.
        // now we have where in pQueryString2 and by in byExpr
        
        // second query
        assign startPos = index(pQueryString2, 'where ':u).
        if not startPos eq 0 then
            assign pQueryString2 = substring(pQueryString2, startPos + 6).
        
        assign startPos = index(pQueryString2, ' by ':u).
        if startPos gt 0 then
            assign byExpr        = byExpr + substring(pQueryString2, startPos)
                   pQueryString2 = trim(substring(pQueryString2, 1, startPos - 1))
                   .
        else
        if pQueryString2 begins 'by ':u then
            assign byExpr        = byExpr + ' ':u + pQueryString2
                   pQueryString2 = '':U
                   .
        
        if not pQueryString2 eq '':u then
            assign pQueryString2 = '( ':u + pQueryString2 + ' )':u.
        // now we have where in pQueryString2 and by in byExpr
        
        // there is a where clause
        if pQueryString1 begins '(':u
        or pQueryString2 begins '(':u
        then
        do:
            assign mergedQry = 'where ':u.
            if pQueryString1 begins '(':u then
                assign mergedQry = mergedQry + pQueryString1.
            
            if pQueryString2 begins '(':u then
            do:
                if pQueryString1 begins '(':u then
                case pJoin:
                    when JoinEnum:AndNot then assign mergedQry = substitute('&1 and not &2':u, mergedQry, pQueryString2).
                    when JoinEnum:OrNot  then assign mergedQry = substitute('&1 or not &2':u, mergedQry, pQueryString2).
                    otherwise                 assign mergedQry = substitute('&1 &2 &3':u, mergedQry, string(pJoin), pQueryString2).
                end case.
                else
                    assign mergedQry = mergedQry + pQueryString2.
            end.
        end.    // we have one or two WHERE
        else
            assign mergedQry = 'where true':u.
        
        if not byExpr eq '':u then
            assign mergedQry = mergedQry + ' ':u + trim(byExpr).
        
        return mergedQry.
    end method.
end class.