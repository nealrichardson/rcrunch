% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/combine-categories.R
\name{collapseCategories}
\alias{collapseCategories}
\title{Combine Categories in place}
\usage{
collapseCategories(var, from, to)
}
\arguments{
\item{var}{A categorical Crunch variable}

\item{from}{A character vector of categories you want to combine.}

\item{to}{A character string with the destination category.}
}
\value{
the variable duly modified
}
\description{
This function allows you to combine the categories of a variable without
making a copy of the variable.
}
\seealso{
\code{\link[=combine]{combine()}}
}
