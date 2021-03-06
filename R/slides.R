# Generics ---------------------------------------------------------------
#' Get and set slide analyses
#'
#' Slides are composed of analyses, which are effectively `CrunchCubes` with some
#' additional metadata. You can get and set a slide's Analysis Catalog with the
#' `analyses` method, and access an individual analysis with `analysis`.
#'
#' You can get the `CrunchCube` from a slide or analysis with the `cube` method and
#' from a `CrunchDeck` with `cubes`. Analyses can be changed by assigning a formula
#' into the `query` function.
#'
#' Advanced users of the API can assign a list to  `analysis<-` to specify settings
#' on the analyses that are not otherwise available in `rcrunch`. The helpers
#' `formulaToSlideQuery()` and `slideQueryEnv()` help you create objects for the
#' `query` and `query_environment`.
#'
#' @param x a `CrunchSlide`, `AnalysisCatalog`, or `Analysis`
#' @param value for the setter, a query
#' @param query For `formulaToSlideQuery()`, a formula that specifies the query, as in
#' `newSlide()`
#' @param dataset For `formulaToSlideQuery()`, a `CrunchDataset` that the variables in
#' `query` refer to.
#' @param weight For `slideQueryEnv()` a crunch variable to use as a weight or `NULL`
#' to indicate no weight should be used.
#' @param filter for `slideQueryEnv()`, a `CrunchFilter` or `CrunchExpression` to filter
#' the slide.
#' @param ... ignored
#'
#' @return an `AnalysisCatalog`, `Analysis`, `Cube`, or `Filter`
#' @rdname analysis-methods
#' @export
#' @examples
#' \dontrun{
#' analysis(slide)
#' cube(slide)
#' cubes(deck)
#' query(slide) <- ~ cyl + wt
#' filter(slide)
#' filter(slide) <- NULL # to remove a filter
#' filter(slide) <- filters(ds)[["My filter"]]
#' }
setGeneric("analyses", function(x) standardGeneric("analyses"))
#' @rdname analysis-methods
#' @export
setGeneric("analysis", function(x) standardGeneric("analysis"))
#' @rdname analysis-methods
#' @export
setGeneric("analysis<-", function(x, value) standardGeneric("analysis<-"))
#' @rdname analysis-methods
#' @export
setGeneric("query<-", function(x, value) standardGeneric("query<-"))
#' @rdname analysis-methods
#' @export
setGeneric("cube", function(x) standardGeneric("cube"))
#' @rdname analysis-methods
#' @export
setGeneric("cubes", function(x) standardGeneric("cubes"))

#' Get or set a slide's display settings
#'
#' A slide's display settings can be modified by assigning a named list
#' @param x a CrunchSlide, Analysis, or AnalysisCatalog
#' @param value a named list, for valid settings see [API documentation](
#' https://crunch.io/api/reference/#get-/datasets/-dataset_id-/decks/-deck_id-/slides/-slide_id-/)
#' @rdname display-settings
#' @export
setGeneric("displaySettings", function(x) standardGeneric("displaySettings"))
#' @rdname display-settings
#' @export
setGeneric("displaySettings<-", function(x, value) standardGeneric("displaySettings<-"))


# Slide Catalog -----------------------------------------------------------

setMethod("initialize", "SlideCatalog", function(.Object, ...) {
    .Object <- callNextMethod()
    order <- crGET(.Object@orders$flat)
    order <- unlist(order$graph)
    .Object@index <- .Object@index[match(order, names(.Object@index))]
    return(.Object)
})

#' @rdname describe-catalog
#' @export
setMethod("names", "SlideCatalog", function(x) titles(x))
#' @rdname describe-catalog
#' @export
setMethod("names<-", "SlideCatalog", function(x, value) titles(x) <- value)

#' @rdname deck-titles
#' @export
setMethod("titles", "SlideCatalog", function(x) getIndexSlot(x, "title"))
#' @rdname deck-titles
#' @export
setMethod("titles<-", "SlideCatalog", function(x, value) {
    setIndexSlot(x, "title", value)
})

#' @rdname deck-titles
#' @export
setMethod("subtitles", "SlideCatalog", function(x) getIndexSlot(x, "subtitle"))
#' @rdname deck-titles
#' @export
setMethod("subtitles<-", "SlideCatalog", function(x, value) {
    setIndexSlot(x, "subtitle", value)
})

#' @rdname crunch-extract
#' @export
setMethod("[[", "SlideCatalog", function(x, i, ...) {
    getEntity(x, i, CrunchSlide)
})

#' @rdname crunch-extract
#' @export
setMethod(
    "[[<-", c("SlideCatalog", "numeric", "missing", "CrunchSlide"),
    function(x, i, j, value) {
        if (length(i) > 1) {
            # TODO, allow assignment of more than one slide
        }
        if (i > length(x) + 1) {
            # TODO what to do with missing slide entries
            i <- length(x) + 1
        }
        if (i <= length(x)) {
            # we are replacing a slide, so return quickly modifying in place
            out <- modifyCatalogInPlace(x, i, j, value)
            return(out)
        }

        n_slides <- length(x)

        payload <- value@body[c("title", "subtitle")]
        anCat <- analyses(value)
        payload$analyses <- lapply(seq_along(anCat), function(i) {
            out <- anCat[[i]]
            # TODO: Make sure API always sends all parts (and no legacy pre-viz_specs)
            # and update fixtures
            out <- out@body[
                na.omit(match(
                    c("query", "query_environment", "display_settings", "transform", "viz_specs"),
                    names(out@body)
                ))
            ]
            out
        })
        payload <- wrapEntity(body = payload)
        crPOST(self(x), body = toJSON(payload))

        if (i < n_slides) {
            # You can't modify the contents of a slide by patching it
            # so we need to add the new slide, delete the original slide,
            # and reorder the slideCatalog.
            # Is ^^^ really true?
            new_order <- moveLastElement(seq_len(n_slides + 1), i)
            reorderSlides(x, new_order)
            with_consent(delete(x[[length(x)]]))
        }
        invisible(refresh(x))
    }
)

#' Move and delete last element of a vector
#' This moves the last element of a vector to an index, then deletes the last
#' element, it is broken out for testing purposes
#'
#' @param v a vector
#' @param idx The index to move the last element to.
#'
#' @return a vector
#' @keywords internal
moveLastElement <- function(v, idx) {
    v[idx] <- v[length(v)]
    out <- v[1:(length(v) - 1)]
    return(out)
}

#' Reorder slides in a CrunchDeck
#'
#' @param x A SlideCatalog
#' @param order The numeric order for slides to be reordered to.
#'
#' @return A SlideCatalog
reorderSlides <- function(x, order) {
    url <- paste0(self(x), "flat")
    payload <- crGET(url)
    payload$graph <- payload$graph[order]
    crPATCH(url, body = toJSON(payload))
    return(refresh(x))
}

# CrunchSlide -------------------------------------------------------------------

# TODO: Find out what the mandatory display settings should be for the app then
# change this list to reflect those settings.
DEFAULT_DISPLAY_SETTINGS <- list(
    percentageDirection = "colPct",
    showEmpty = FALSE,
    showMean = FALSE,
    vizType = "table",
    countsOrPercents = "percent",
    decimalPlaces = 1L,
    showSignif = TRUE,
    currentTab = 0L
)

#' Append a new slide to a Crunch Deck
#'
#' @param deck A Crunch Deck
#' @param query A formula definition of a query to be used by the slide. This is
#' similar to CrunchCube query
#' @param display_settings (optional) A list of display settings. If omitted,
#' slide will be a table of column percentages with hypothesis test highlighting
#' enabled. The most common setting used is `vizType`, which can be:
#' `table`, `groupedBarPlot`, `stackedBarPlot`, `horizontalBarPlot`,
#' `horizontalStackedBarPlot`, `donut`, and (if the second variable in the
#' query formula is a wave variable) `timeplot`.
#' In addition, `showValueLabels` (logical) controls whether the web app and
#' exports show labels on bars or arcs of donuts.
#' @param title The slide's title
#' @param subtitle The slide's subtitle
#' @param ... Further options to be passed on to the API
#'
#' @return CrunchSlide object
#' @export
#'
#' @examples
#' \dontrun{
#' newSlide(
#'     main_deck,
#'     ~ cyl + wt,
#'     title = "Cyl and Weight",
#'     subtitle = "2017 Data"
#' )
#'
#' # Grouped bar plot
#' newSlide(
#'     main_deck,
#'     ~ approval + age4,
#'     title = "Approval by age group",
#'     display_settings = list(
#'         vizType = "groupedBarPlot",
#'         showValueLabels = TRUE
#'     ),
#'     subtitle = "2017 Data"
#' )
#'
#' # Horizontal stacked bars
#' newSlide(
#'     main_deck,
#'     ~ approval + age4,
#'     title = "Approval by age group",
#'     display_settings = list(
#'         vizType = "horizontalStackedBarPlot"
#'     ),
#'     subtitle = "2017 Data"
#' )
#'
#' # A donut is only suitable for a single variable
#' newSlide(
#'     main_deck,
#'     ~ approval,
#'     title = "Approval of new feature",
#'     display_settings = list(
#'         vizType = "donut",
#'         showValueLabels = FALSE
#'     ),
#'     subtitle = "2017 Data"
#' )
#'
#' # Can specify advanced options by specifying `analyses` directly
#' # `formulaToSlideQuery()` and `slideQueryEnv()` help describe the API
#' newSlide(
#'     main_deck,
#'     title = "custom slide",
#'     analyses = list(list(
#'         query = formulaToSlideQuery(~categories(fav_array)+subvariables(fav_array), ds),
#'         query_environment = slideQueryEnv(filter = filters(ds)[[1]]),
#'         display_settings = list(viz_type = list(value = "table")),
#'         viz_specs =  list(
#'             default = list(
#'                 format = list(
#'                     decimal_places = list(percentages = 0L, other = 2L),
#'                     show_empty = FALSE
#'                 )
#'              ),
#'              table = list(
#'              measures = c("col_percent", "pairwise_t_test"),
#'              page_layout = list(
#'                  rows = list(
#'                      top = list(),
#'                      bottom = c("base_unweighted", "scale_mean", "significant_columns")
#'                  ),
#'                  measure_layout = "long"
#'              ),
#'              pairwise_comparison = list(sig_threshold = c(0.05, 0.01)),
#'              format = list(pval_colors = FALSE)
#'             )
#'         )
#'     ))
#' )
#' }
newSlide <- function(deck,
                     query = NULL,
                     display_settings = list(),
                     title = "",
                     subtitle = "",
                     ...) {
    stopifnot(inherits(query, "formula") || is.null(query))
    settings <- modifyList(DEFAULT_DISPLAY_SETTINGS, display_settings)
    settings <- wrapDisplaySettings(settings)

    ds <- loadDataset(datasetReference(deck))

    payload <- list(title = title, subtitle = subtitle, ...)
    if ("analyses" %in% names(payload) && !is.null(query)) {
        halt("Cannot specify both a `query` and `analyses` for `newSlide()`")
    }
    if (!"analyses" %in% names(payload) && is.null(query)) {
        halt("Must specify either a `query` or `analyses` for `newSlide()`")
    }
    if (!"analyses" %in% names(payload) && length(display_settings) != 0) {
        warning(
            "`display_settings` are ignored if `analyses` are defined directly for `newSlide()`"
        )
    }

    if (!is.null(query)) {
        # Technically multiple analyses per slide are allowed (for profiles), but this
        # isn't supported in the R package, and if someone really wants it, they could
        # form the analyses object themselves
        payload[["analyses"]] <- list(list(
            query = formulaToCubeQuery(query, ds),
            display_settings = settings
        ))
    }

    payload <- wrapEntity(body = payload)
    url <- crPOST(shojiURL(deck, "catalogs", "slides"), body = toJSON(payload))
    return(CrunchSlide(crGET(url)))
}

#' @rdname crunch-extract
#' @export
setMethod("[[", "CrunchSlide", function(x, i, ...) {
    an_cat <- analyses(x)
    return(an_cat[[i]])
})
#' @rdname crunch-extract
#' @export
setMethod("[[<-", "CrunchSlide", function(x, i, j, value) {
    an_cat <- analyses(x)
    an_cat[[i]] <- value
    invisible(refresh(x))
})

#' @rdname deck-titles
#' @export
setMethod("title", "CrunchSlide", function(x) {
    return(x@body$title)
})

#' @rdname deck-titles
#' @export
setMethod("title<-", "CrunchSlide", function(x, value) {
    setEntitySlot(x, "title", value)
})

#' @rdname deck-titles
#' @export
setMethod("subtitle", "CrunchSlide", function(x) {
    return(x@body$subtitle)
})

#' @rdname deck-titles
#' @export
setMethod("subtitle<-", "CrunchSlide", function(x, value) {
    setEntitySlot(x, "subtitle", value)
})

#' @rdname analysis-methods
#' @export
setMethod("analyses", "CrunchSlide", function(x) {
    AnalysisCatalog(crGET(shojiURL(x, "catalogs", "analyses")))
})


#' @rdname analysis-methods
#' @export
setMethod("analysis", "CrunchSlide", function(x) {
    out <- AnalysisCatalog(crGET(shojiURL(x, "catalogs", "analyses")))
    return(out[[1]])
})

#' @rdname analysis-methods
#' @export
setMethod("analysis<-", c("CrunchSlide", "formula"), function(x, value) {
    analysis <- analyses(x)[[1]]
    query(analysis) <- value
    return(invisible(x))
})

#' @rdname analysis-methods
#' @export
setMethod("analysis<-", c("CrunchSlide", "Analysis"), function(x, value) {
    analysis_cat <- analyses(x)
    return(invisible(modifyCatalogInPlace(analysis_cat, 1, NULL, value)))
})

#' @rdname analysis-methods
#' @export
setMethod("analysis<-", c("CrunchSlide", "list"), function(x, value) {
    payload <- wrapEntity(body = value)
    url <- self(analysis(x))
    crPATCH(url, body = toJSON(payload))
    invisible(refresh(x))
})

#' @rdname analysis-methods
#' @export
setMethod("filter", "CrunchSlide", function(x, ...) {
    analysis <- analyses(x)[[1]]
    return(filter(analysis))
})

#' @rdname analysis-methods
#' @export
setMethod("filter<-", c("CrunchSlide", "ANY"), function(x, value) {
    # check that there is only on analysis?
    first_analysis <- analyses(x)[[1]]
    filter(first_analysis) <- value
    return(invisible(x))
})

#' @rdname analysis-methods
#' @export
setMethod("query<-", "CrunchSlide", function(x, value) {
    analysis <- analyses(x)[[1]]
    query(analysis) <- value
    return(invisible(x))
})

#' @rdname analysis-methods
#' @export
setMethod("cubes", "CrunchSlide", function(x) cubes(analyses(x)))
#' @rdname analysis-methods
#' @export
setMethod("cube", "CrunchSlide", function(x) cube(analyses(x)[[1]]))
#' @rdname display-settings
#' @export
setMethod("displaySettings", "CrunchSlide", function(x) displaySettings(analyses(x)))
#' @rdname display-settings
#' @export
setMethod("displaySettings<-", "CrunchSlide", function(x, value) {
    an_cat <- analyses(x)
    displaySettings(an_cat) <- value
    return(invisible(x))
})

# AnalysisCatalog --------------------------------------------------------------

setMethod("initialize", "AnalysisCatalog", function(.Object, ...) {
    .Object <- callNextMethod()
    if (length(.Object@index) > 1) {
        order <- crGET(.Object@orders$order)
        order <- unlist(order$graph)
        .Object@index <- .Object@index[match(order, names(.Object@index))]
    }
    return(.Object)
})

#' @rdname crunch-extract
#' @export
setMethod("[[", "AnalysisCatalog", function(x, i, ...) {
    getEntity(x, i, Analysis)
})
#' @rdname crunch-extract
#' @export
setMethod(
    "[[<-", c("AnalysisCatalog", "numeric", "missing", "formula"),
    function(x, i, j, value) {
        if (i > length(x)) {
            halt(
                "Index out of bounds, you can only assign a formula to an ",
                "existing analysis."
            )
        }
        analysis <- x[[i]]
        query(analysis) <- value
        invisible(refresh(x))
    }
)
#' @rdname crunch-extract
#' @export
setMethod(
    "[[<-", c("AnalysisCatalog", "numeric", "missing", "Analysis"),
    function(x, i, j, value) {
        if (length(i) > 1) {
            # TODO, recurse through i
        }

        if (i > length(x) + 1) {
            # TODO what to do with adding an analysis that's not the next one.
        }
        # TODO: Make sure API always sends all parts (and no legacy pre-viz_specs)
        # and update fixtures
        payload <- value@body[
            na.omit(match(
                c("query", "display_settings", "query_environment", "viz_specs", "transforms"),
                names(value@body)
            ))
        ]
        payload <- wrapEntity(body = payload)
        if (i <= length(x)) {
            url <- names(x@index)[i]
            crPATCH(url, body = toJSON(payload))
        } else {
            crPOST(self(x), body = toJSON(payload))
        }
        invisible(refresh(x))
    }
)
#' @rdname crunch-extract
#' @export
setMethod(
    "[[<-", c("AnalysisCatalog", "numeric", "missing", "list"),
    function(x, i, j, value) {
        all_fmla <- vapply(value, function(x) inherits(x, "formula"), logical(1))
        if (any(!all_fmla)) {
            halt("Entry ", which(!all_fmla), " is not a formula")
        }
        if (length(i) != length(value)) {
            noun <- if (length(i) == 1) " analysis." else " analyses."
            halt(
                "Invalid assignment. You tried to assign ", length(value),
                " formulas to ", length(i), noun
            )
        }
        mapply(function(analysis, fmla) {
            analysis <- fmla
        }, analysis = x[[i]], fmla = value)
    }
)

#' @rdname analysis-methods
#' @export
setMethod("cubes", "AnalysisCatalog", function(x) {
    lapply(seq_along(x@index), function(i) cube(x[[i]]))
})

#' @rdname display-settings
#' @export
setMethod("displaySettings", "AnalysisCatalog", function(x) {
    settings_list <- lapply(seq_along(x), function(i) {
        displaySettings(x[[i]])
    })
    if (length(settings_list) == 1) {
        return(settings_list[[1]])
    } else {
        return(settings_list)
    }
})
#' @rdname display-settings
#' @export
setMethod("displaySettings<-", c("AnalysisCatalog", "list"), function(x, value) {
    analyses <- lapply(seq_along(x), function(i) x[[i]])
    lapply(analyses, function(x) displaySettings(x) <- value)
})


# Analysis ----------------------------------------------------------------
#' @rdname analysis-methods
#' @export
setMethod("query<-", c("Analysis", "formula"), function(x, value) {
    ds <- loadDataset(datasetReference(x))
    payload <- list(query = formulaToCubeQuery(value, data = ds))
    payload <- wrapEntity(body = payload)
    crPATCH(self(x), body = toJSON(payload))
    return(invisible(refresh(x)))
})

#' @rdname analysis-methods
#' @export
formulaToSlideQuery <- function(query, dataset) {
    formulaToCubeQuery(query, dataset)
}

#' @rdname analysis-methods
#' @export
setMethod("cube", "Analysis", function(x) {
    CrunchCube(crGET(
        cubeURL(x),
        query = list(query = toJSON(x@body$query)),
        filter = toJSON(x@body$query_environment$filter)
    ))
})
#' @rdname display-settings
#' @export
setMethod("displaySettings", "Analysis", function(x) {
    lapply(x@body$display_settings, function(x) x$value)
})
#' @rdname display-settings
#' @export
setMethod("displaySettings<-", "Analysis", function(x, value) {
    settings <- modifyList(displaySettings(x), value)
    settings <- wrapDisplaySettings(settings)
    payload <- list(display_settings = settings)
    payload <- wrapEntity(body = payload)
    crPATCH(self(x), body = toJSON(payload))
    invisible(refresh(x))
})

# This processes a names list of display setting values to the form that is
# required by the API.
wrapDisplaySettings <- function(settings) {
    return(lapply(settings, function(x) list(value = x)))
}

#' @rdname analysis-methods
#' @export
setMethod("filter", "Analysis", function(x, ...) {
    filt <- x@body$query_environment$filter
    if (length(filt) == 0) {
        return(NULL)
    } else if (length(filt) == 1 && "filter" %in% names(filt[[1]])) {
        # a saved filter
        return(CrunchFilter(crGET(filt[[1]]$filter)))
    } else {
        # an adhoc filter
        adhoc_expr <- CrunchExpr(expression = fixAdhocFilterExpression(filt[[1]]))
        return(adhoc_expr)
    }
})

#' @rdname analysis-methods
#' @export
setMethod("filter", "ANY", function(x, ...) {
    for (searchpath in search()) {
        func <- get("filter", as.environment(searchpath))
        if (!identical(func, crunch::filter)) {
            return(func(x, ...))
        }
    }
    halt("No method found for filter for object of type ", dQuote(methods::getClass(x))) # nocov
})

#' @rdname analysis-methods
#' @export
setMethod("filter<-", "CrunchSlide", function(x, value) {
    analysis <- analyses(x)[[1]]
    filter(analysis) <- value
    return(invisible(x))
})

#' @rdname analysis-methods
#' @export
setMethod("filter<-", c("Analysis", "CrunchLogicalExpr"), function(x, value) {
    halt("Setting adhoc filters on decks is unsupported")
    # the following _should_ work, however query_environment filters must include
    # dataset references (which our expression to ZCL converter does not support)
    # This should be fixed in https://www.pivotaltracker.com/story/show/157399444
    # once query_environment is changed to work like every other expression, the
    # following should just work:
    # return(set_query_env_slot(x, filter = list(value@expression)))
})

#' @rdname analysis-methods
#' @export
setMethod("filter<-", c("Analysis", "CrunchFilter"), function(x, value) {
    # crPATCH(self(x), body = toJSON(frmt))
    return(set_query_env_slot(x, filter = list(self(value))))
})

#' @rdname analysis-methods
#' @export
setMethod("filter<-", c("Analysis", "NULL"), function(x, value) {
    # crPATCH(self(x), body = toJSON(frmt))
    return(set_query_env_slot(x, filter = list()))
})

#' @rdname analysis-methods
#' @export
slideQueryEnv <- function(weight, filter) {
    if (missing(weight) && missing(filter)) {
        halt("Must specify at least one of `weight` or `filter`")
    }
    out <- list()
    if (!missing(weight)) {
        out$weight <- if (is.null(weight)) list() else list(self(weight))
    }
    if (!missing(filter)) {
        if (is.null(filter)) {
            out$filter <- list()
        } else if (is.CrunchExpr(filter)) {
            # Reasoning explained in `setMethod("filter<-", c("Analysis", "CrunchLogicalExpr")`
            halt("ad-hoc filters not supported for slides")
            # out$filter <- list(filter@expression)
        } else {
            out$filter <- list(self(filter))
        }
    }
    out
}

#' @rdname display-settings
#' @export
setMethod("cubes", "CrunchDeck", function(x) {
    out <- lapply(seq_len(length(x)), function(i) {
        cubes <- cubes(x[[i]])
        # If a slide has several analyses we should return a sublist of
        # cubes, but most of the time they will have one analysis so not
        # including the sublist is preferable.
        if (length(cubes) == 1) {
            cubes <- cubes[[1]]
        }
        return(cubes)
    })
    names(out) <- titles(x)
    return(out)
})


#' @rdname weight
#' @export
setMethod("weight", "CrunchSlide", function(x) {
    analysis <- analyses(x)[[1]]
    return(weight(analysis))
})

#' @rdname weight
#' @export
setMethod("weight<-", c("CrunchSlide", "ANY"), function(x, value) {
    # check that there is only on analysis?
    first_analysis <- analyses(x)[[1]]
    weight(first_analysis) <- value
    return(invisible(x))
})

#' @rdname weight
#' @export
setMethod("weight", "Analysis", function(x) {
    wt <- x@body$query_environment$weight
    if (length(wt) == 0) {
        return(NULL)
    }
    full_ds <- loadDataset(datasetReference(VariableEntity(x)))
    wt_pos <- which(urls(allVariables(full_ds)) == wt)
    filt <- filter(x)
    if (!is.null(filt)) {
        filt <- CrunchLogicalExpr(expression = filt@body[["expression"]])
    }
    CrunchVariable(allVariables(full_ds)[[wt_pos]], filter = filt)
})

#' @rdname weight
#' @export
setMethod("weight<-", c("Analysis", "CrunchVariable"), function(x, value) {
    if (!is.weightVariable(value)) halt(paste0(
        "Variable '", alias(value), "' is not a weightVariable"
    ))
    return(set_query_env_slot(x, weight = self(value)))
})

#' @rdname weight
#' @export
setMethod("weight<-", c("Analysis", "NULL"), function(x, value) {
    return(set_query_env_slot(x, weight = NULL))
})

# TODO: setMethod("weight<-", c("Analysis", "CrunchVariable") method to use alias?

# Want to update filter/weight components separately so that we don't
# remove something accidentally.
set_query_env_slot <- function(x, filter, weight) {
    query_env <- slot(x, "body")[["query_environment"]]
    # The single "[" <- list() notation allows NULLs in weight rather than just removing weight
    if (!missing(filter)) query_env["filter"] <- list(filter)
    if (!missing(weight)) query_env["weight"] <- list(weight)

    setEntitySlot(x, "query_environment", query_env)
}
