VERSION = $(shell grep ^Version DESCRIPTION | sed s/Version:\ //)

doc:
	R --slave -e 'devtools::document()'
	git add --all man/*.Rd

test:
	R CMD INSTALL --install-tests .
	export NOT_CRAN=true && R --slave -e 'library(httptest); setwd(file.path(.libPaths()[1], "crunch", "tests")); options(crunch.check.updates=FALSE); system.time(test_check("crunch", filter="${file}", reporter=ifelse(nchar("${r}"), "${r}", "summary")))'

lint:
	R --slave -e 'styler::style_pkg(transformers = styler::tidyverse_style(indent_by = 4))'

deps:
	R --slave -e 'Nexus <- "https://rproxy:I0VktB3jZdplfsEgeiAR@ui.nexus.crint.net/repository/rcrunch/"; if (!dir.exists(file.path(.libPaths()[1], "devtools"))) install.packages("devtools", repo=Nexus); devtools::install_deps(dependencies=TRUE)'

install-ci: deps
	R -e 'devtools::session_info(installed.packages()[, "Package"])'

test-ci:
	R --slave -e 'library(covr); to_cobertura(package_coverage(quiet=FALSE))'

clean:
	R --slave -e 'options(crunch.api=getOption("test.api"), crunch.email=getOption("test.user"), crunch.pw=getOption("test.pw")); library(crunch); login(); lapply(urls(datasets()), crDELETE)'

build: doc
	R CMD build .

check: build
	-unset INTEGRATION && export _R_CHECK_CRAN_INCOMING_REMOTE_=FALSE && R CMD CHECK --as-cran crunch_$(VERSION).tar.gz
    # cd crunch.Rcheck/crunch/doc/ && ls | grep .html | xargs -n 1 egrep "<pre><code>.. NULL" >> ../../../vignette-errors.log
	rm -rf crunch.Rcheck/
    # cat vignette-errors.log
    # rm vignette-errors.log

release: build
	-unset INTEGRATION && R CMD CHECK --as-cran crunch_$(VERSION).tar.gz
	rm -rf crunch.Rcheck/

vdata:
	cd vignette-data && R -f make-vignette-rdata.R

man: doc
	R CMD Rd2pdf man/ --force

md:
	R CMD INSTALL --install-tests .
	mkdir -p inst/doc
	R -e 'setwd("vignettes"); lapply(dir(pattern="Rmd"), knitr::knit, envir=globalenv())'
	mv vignettes/*.md inst/doc/
	-cd inst/doc && ls | grep .md | xargs -n 1 sed -i '' 's/.html)/.md)/g'
	-cd inst/doc && ls | grep .md | xargs -n 1 egrep "^.. Error"

build-vignettes: md
	R -e 'setwd("inst/doc"); lapply(dir(pattern="md"), function(x) markdown::markdownToHTML(x, output=sub("\\\\.md", ".html", x)))'
	cd inst/doc && ls | grep .html | xargs -n 1 sed -i '' 's/.md)/.html)/g'
	# That sed isn't working, fwiw
	open inst/doc/crunch.html

spell:
	R --slave -e 'spelling::spell_check_package(vignettes=TRUE, lang="en_US")'

covr:
	R --slave -e 'Sys.setenv(R_TEST_USER=getOption("test.user"), R_TEST_PW=getOption("test.pw"), R_TEST_API=getOption("test.api")); library(covr); cv <- package_coverage(); df <- covr:::to_shiny_data(cv)[["file_stats"]]; cat("Line coverage:", round(100*sum(df[["Covered"]])/sum(df[["Relevant"]]), 1), "percent\\n"); shine(cv, browse=TRUE)'

compress-fixtures:
	R --slave -e 'tar("inst/mocks.tgz", files = "mocks", compression = "gzip")'
