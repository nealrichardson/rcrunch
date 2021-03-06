getSummary <- function(x) {
    url <- shojiURL(x, "views", "summary")
    out <- crGET(url, query = list(filter = toJSON(zcl(activeFilter(x)))))
    if (is.Datetime(x)) {
        toR <- columnParser("datetime")
        for (i in c("min", "max")) out[[i]] <- toR(out[[i]])
    }
    return(out)
}

#' Table function for Crunch objects
#'
#' @param ... CrunchVariables to tabulate
#' @param exclude see [`base::table`]
#' @param useNA see [`base::table`]
#' @param dnn see [`base::table`]
#' @param deparse.level see [`base::table`]
#' @return a table object
#' @seealso [`base::table`]
#' @export
table <- function(..., exclude, useNA = c("no", "ifany", "always"), dnn, deparse.level) {
    m <- match.call()

    dots <- list(...)
    are.vars <- vapply(
        dots,
        function(x) is.variable(x) || is.CrunchExpr(x),
        logical(1)
    )
    if (length(are.vars) && all(are.vars)) {
        dims <- unlist(lapply(dots, varToDim), recursive = FALSE)
        names(dims) <- NULL
        query <- list(
            dimensions = dims,
            measures = list(count = zfunc("cube_count"))
        )
        ## Check for filters
        filters <- vapply(
            dots,
            function(x) toJSON(zcl(activeFilter(x))),
            character(1)
        )
        if (!all(filters == filters[1])) {
            halt("Filter expressions in variables must be identical")
        }
        query <- list(
            query = toJSON(query),
            filter = filters[1]
        )
        cube_url <- cubeURL(dots[[1]])
        cube <- CrunchCube(crGET(cube_url, query = query), useNA = match.arg(useNA))
        return(as.table(as.array(cube)))
    } else if (any(are.vars)) {
        halt(
            "Cannot currently tabulate Crunch variables with ",
            "non-Crunch vectors"
        )
    } else {
        m[[1]] <- quote(base::table)
        return(eval.parent(m))
    }
}

# setGeneric("table", signature="...")
# ## @export
# setMethod("table", "CategoricalVariable", CategoricalVariable.table)

#' Summary methods for Crunch Variables
#'
#' @param object A Variable
#' @param ... additional arguments, ignored (they're in the summary.default)
#' signature
#' @return a summary response. Categorical variable summaries should work like
#' summary.factor; Numeric variables should be like summary.numeric. Other
#' Variable types are not yet supported.
#' @name crunch-summary
#' @keywords internal
#' @export
summary.CategoricalVariable <- function(object, ...) {
    tab <- table(object)
    tab <- tab[order(tab, decreasing = TRUE)]
    class(tab) <- c("CategoricalVariableSummary", class(tab))
    attr(tab, "varname") <- getNameAndType(object)
    return(tab)
}

#' @export
print.CategoricalVariableSummary <- function(x, ...) {
    print(data.frame(Count = as.numeric(x), row.names = names(x)))
}

#' @rdname crunch-summary
#' @export
summary.NumericVariable <- function(object, ...) {
    summ <- getSummary(object)
    fivenum <- sapply(summ$fivenum, function(x) x[[2]])
    out <- c(fivenum[1:3], summ$mean, fivenum[4:5])
    if (summ$missing_count) {
        out <- c(out, summ$missing_count)
    }
    names <- c("Min.", "1st Qu.", "Median", "Mean", "3rd Qu.", "Max.", "NA's")
    names(out) <- names[seq_along(out)]
    class(out) <- c("NumericVariableSummary", "summaryDefault", "table")
    attr(out, "varname") <- getNameAndType(object)
    return(out)
}
