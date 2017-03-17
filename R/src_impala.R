# Copyright 2017 Cloudera Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# register virtual classes

#' @export
#' @importFrom methods setOldClass
setOldClass("src_impala")

#' @export
#' @importFrom methods setOldClass
setOldClass("tbl_impala")

#' Do cool stuff
#'
#' @export
#' @importFrom DBI dbConnect
#' @importFrom DBI dbGetInfo
#' @importFrom dplyr src_sql
#' @importFrom methods getClass
#' @importFrom methods setClass
src_impala <- function(drv, ..., auto_disconnect = FALSE) {
  if (!requireNamespace("assertthat", quietly = TRUE)) {
    stop("assertthat is required to use src_impala", call. = FALSE)
  }
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("dplyr is required to use src_impala", call. = FALSE)
  }
  if (!requireNamespace("DBI", quietly = TRUE)) {
    stop("DBI is required to use src_impala", call. = FALSE)
  }
  if(inherits(drv, "src_impala")) {
    con <- drv
    return(con)
  }
  if(!inherits(drv, "DBIDriver")) {
    stop("drv must be a DBI-compatible driver object or an existing src_impala object")
  }

  con <- dbConnect(drv, ...)

  disco <- if (isTRUE(auto_disconnect)) db_disconnector(con)

  r <- dbGetQuery(
    con,
    "SELECT version() AS version, current_database() AS dbname;"
  )
  if(inherits(con, "JDBCConnection")) {
    l <- getNamedArgs_JDBCDriver(...)
    info <- list(
      user = l$user,
      url = sub(".+?://", "", sub(paste0("(:\\d*/)", r$dbname), "\\1", l$url)),
      version = r$version,
      dbname = r$dbname
    )
  } else if(inherits(con, "OdbcConnection")) {
    l <- getNamedArgs_OdbcDriver(...)
    if(!is.null(l$.connection_string)) {
      if(grepl("Host=(.+?);", l$.connection_string, ignore.case = TRUE)) {
        l$host <- sub(".*Host=(.+?);.*", "\\1", l$.connection_string, ignore.case = TRUE)
      }
      if(grepl("Port=(.+?);", l$.connection_string, ignore.case = TRUE)) {
        l$port <- sub(".*Port=(.+?);.*", "\\1", l$.connection_string, ignore.case = TRUE)
      }
      if(grepl("UID=(.+?);", l$.connection_string, ignore.case = TRUE)) {
        l$uid <- sub(".*UID=(.+?);.*", "\\1", l$.connection_string, ignore.case = TRUE)
      }
    }
    info <- list(
      dsn = l$dsn,
      user = l$uid,
      host = l$host,
      port = l$port,
      version = r$version,
      dbname = r$dbname
    )
  } else {
    info <- dbGetInfo(con)
  }
  info$package <- attr(attr(getClass(class(con)[1]), "className"), "package")

  setClass("impala_connection", contains = class(con), where = parent.frame())
  con <- structure(con, class = c("impala_connection", class(con)))

  src_sql("impala", con = con, disco = disco, info = info)
}

#' @export
#' @importFrom dplyr src_desc
src_desc.src_impala <- function(x) {
  info <- x$info
  info$version <-
    sub("\\s?.?(buil|release).*$", "", info$version, ignore.case = TRUE)
  if(!"url" %in% names(info)) {
    if(!is.null(info$host) && !is.null(info$port)) {
      info$url <- paste0(info$host, ":", info$port)
    } else if(!is.null(info$host)) {
      info$url <- info$host
    } else if(!is.null(info$dsn)) {
      info$url <- paste0(info$dsn)
    }
  } else {
    info$url <- paste0(info$url)
  }
  if(!is.null(info$user) && info$user != "") {
    info$user <- paste0(info$user, "@")
  }
  paste0(info$version, " through ", info$package, " [", info$user, info$url, "/", info$dbname, "]")
}

#' @export
#' @importFrom dplyr tbl
#' @importFrom dplyr tbl_sql
tbl.src_impala <- function(src, from, ...) {
  tbl_sql("impala", src = src, from = from, ...)
}

#' @export
#' @importFrom dplyr sql_escape_ident
sql_escape_ident.impala_connection <- function(con, x) {
  sql_quote(x, "`")
}

#' @export
#' @importFrom dplyr sql_escape_string
sql_escape_string.impala_connection <- function(con, x) {
  sql_quote(x, "'")
}

#' @export
#' @importFrom dplyr base_agg
#' @importFrom dplyr base_scalar
#' @importFrom dplyr base_win
#' @importFrom dplyr build_sql
#' @importFrom dplyr sql
#' @importFrom dplyr sql_prefix
#' @importFrom dplyr sql_translate_env
#' @importFrom dplyr sql_translator
#' @importFrom dplyr sql_variant
sql_translate_env.impala_connection <- function(con) {
  sql_variant(
    sql_translator(
      .parent = base_scalar,

      # type conversion functions
      as.character = function(x) build_sql("cast(", x, " as string)"),
      as.string = function(x) build_sql("cast(", x, " as string)"),
      as.char = function(x, len) build_sql("cast(", x, " as char(", as.integer(len),"))"),
      as.varchar = function(x, len) build_sql("cast(", x, " as varchar(", as.integer(len),"))"),
      as.boolean = function(x) build_sql("cast(", x, " as boolean)"),
      as.logical = function(x) build_sql("cast(", x, " as boolean)"),
      as.numeric = function(x) build_sql("cast(", x, " as double)"),
      as.int = function(x) build_sql("cast(", x, " as int)"),
      as.integer = function(x) build_sql("cast(", x, " as int)"),
      as.bigint = function(x) build_sql("cast(", x, " as bigint)"),
      as.smallint = function(x) build_sql("cast(", x, " as smallint)"),
      as.tinyint = function(x) build_sql("cast(", x, " as tinyint)"),
      as.double = function(x) build_sql("cast(", x, " as double)"),
      as.real = function(x) build_sql("cast(", x, " as real)"),
      as.float = function(x) build_sql("cast(", x, " as float)"),
      as.single = function(x) build_sql("cast(", x, " as float)"),
      as.decimal = function(x, pre = NULL, sca = NULL) {
        if(is.null(pre)) {
          build_sql("cast(", x, " as decimal)")
        } else {
          if(is.null(sca)) {
            build_sql("cast(", x, " as decimal(", as.integer(pre), "))")
          } else {
            build_sql("cast(", x, " as decimal(", as.integer(pre),",", as.integer(sca), "))")
          }
        }
      },
      as.timestamp = function(x) build_sql("cast(", x, " as timestamp)"),

      # mathematical functions
      is.nan = sql_prefix("is_nan"),
      is.infinite = sql_prefix("is_inf"),
      is.finite = sql_prefix("!is_inf"),
      log = function(x, base = exp(1)) {
        if (base != exp(1)) {
          build_sql("log(", base, ", ", x, ")")
        } else {
          build_sql("ln(", x, ")")
        }
      },
      pmax = sql_prefix("greatest"),
      pmin = sql_prefix("least"),

      # date and time functions (work like lubridate)
      week = sql_prefix("weekofyear"),
      yday = sql_prefix("dayofyear"),
      mday = sql_prefix("day"),
      wday = function(x, label = FALSE, abbr = TRUE) {
        if(label) {
          if(abbr) {
            build_sql("substring(dayname(", x, "),1,3)")
          } else {
            build_sql("dayname(", x, ")")
          }
        } else {
          build_sql("dayofweek(", x, ")")
        }
      },

      # conditional functions
      na_if = sql_prefix("nullif", 2),

      # string functions
      paste = function(..., sep = " ") {
        sql(paste0("concat_ws(", sql_escape_string(con, sep), ",", paste(list(...), collapse=","), ")"))
        # TBD: simplify this by passing con to build_sql?
      },
      paste0 = function(...) {
        build_sql("concat(", sql(paste(list(...), collapse=",")), ")")
      }

    ),
    sql_translator(
      .parent = base_agg,
      n = function() sql("count(*)"),
      median = sql_prefix("appx_median"),
      sd =  sql_prefix("stddev"),
      var = sql_prefix("variance"),
      paste = function(x, sep = " ") {
        sql(paste0("group_concat(", x, ",", sql_escape_string(con, sep), ")"))
      },
      paste0 = function(x) {
        build_sql("group_concat(", x, ",'')")
      }
    ),
    base_win
  )
}

#' @export
#' @importFrom dplyr intersect
intersect.tbl_impala <- function(x, y, copy = FALSE, ...) {
  stop("Impala does not support intersect operations.")
}

#' @export
#' @importFrom dplyr setdiff
setdiff.tbl_impala <- function(x, y, copy = FALSE, ...) {
  stop("Impala does not support setdiff operations.")
}


#' @export
#' @importFrom dplyr build_sql
#' @importFrom dplyr ident
#' @importFrom dplyr is.ident
#' @importFrom dplyr sql
#' @importFrom dplyr sql_subquery
#' @importFrom stats setNames
#' @importFrom utils getFromNamespace
sql_subquery.impala_connection <- function(con, from, name = getFromNamespace("unique_name", "dplyr")(), ...) {
  if (is.ident(from)) {
    setNames(from, name)
  } else {
    from <- sql(sub(";$", "", from))
    if(grepl("\\sORDER BY\\s", from) && !grepl("\\sLIMIT\\s", from)) {
      from <- sql(paste(from, "LIMIT 9223372036854775807"))
    }
    build_sql("(", from, ") ", ident(name %||% getFromNamespace("random_table_name", "dplyr")()), con = con)
  }
}

#' @export
#' @importFrom assertthat assert_that
#' @importFrom assertthat is.string
#' @importFrom assertthat is.flag
#' @importFrom dplyr copy_to
copy_to.src_impala <- function(dest, df, name = deparse(substitute(df)), overwrite = FALSE,
                               types = NULL, temporary = TRUE, unique_indexes = NULL, indexes = NULL,
                               analyze = TRUE, external = FALSE, force = FALSE, ...) {

  # don't try to insert large data frames with INSERT ... VALUES()
  if(prod(dim(df)) > 1e3L) {
    stop("Data frame ", name, " is too large. copy_to currently only supports very small data frames.")
  }

  # TBD: add params to control external, row format, stored as, location, etc.
  # (or take them in the ... and pass them to db_create_table())

  assert_that(
    is.data.frame(df),
    is.string(name),
    is.flag(overwrite),
    is.flag(temporary),
    is.flag(analyze)
  )
  if(temporary) {
    stop("Impala does not support temporary tables. Set temporary = FALSE in copy_to().")
  }
  class(df) <- "data.frame"
  con <- con_acquire(dest)
  tryCatch({
    types <- types %||% db_data_type(con, df)
    names(types) <- names(df) # TBD: convert illegal names to legal names?
    tryCatch({
      db_create_table(con, name, types, temporary = FALSE, external = external, force = force, ...)
      db_insert_into(con, name, df, overwrite)
      if (analyze) {
        db_analyze(con, name)
      }
    }, error = function(err) {
      stop(err)
    })
  }, finally = {
    con_release(dest, con)
  })
  invisible(tbl(dest, name))
}

#' @export
#' @importFrom assertthat assert_that
#' @importFrom assertthat is.string
#' @importFrom assertthat is.flag
#' @importFrom dplyr %>%
#' @importFrom dplyr compute
#' @importFrom dplyr group_by_
#' @importFrom dplyr groups
#' @importFrom dplyr op_vars
#' @importFrom dplyr select_
#' @importFrom dplyr sql_render
#' @importFrom dplyr tbl
#' @importFrom utils getFromNamespace
compute.tbl_impala <- function(x, name, temporary = TRUE, external = FALSE,
                               overwrite = FALSE, force = FALSE, analyze = FALSE, ...) {

  # TBD: add params to control external, row format, stored as, location, etc.
  # (or take them in the ... and pass them to db_create_table())

  assert_that(
    is.string(name),
    is.flag(temporary),
    is.flag(external),
    is.flag(overwrite),
    is.flag(force),
    is.flag(analyze)
  )
  if(temporary) {
    stop("Impala does not support temporary tables. Set temporary = FALSE in compute().")
  }

  con <- con_acquire(x$src)
  tryCatch({
    vars <- op_vars(x)
    #x_aliased <- select(x, !!! symbols(vars))
    x_aliased <- select_(x, .dots = vars)
    db_save_query(con, sql_render(x_aliased, con), name = name, temporary = FALSE, external = external,
                  overwrite = overwrite, force = force, analyze = analyze, ...)
  }, finally = {
    con_release(x$src, con)
  })

  #tbl(x$src, name) %>%
  #  group_by(!!! symbols(op_grps(x))) %>%
  #  getFromNamespace("add_op_order", "dplyr")(op_sort(x))
  tbl(x$src, name) %>% group_by_(.dots = groups(x))
}

#' @export
#' @importFrom assertthat assert_that
#' @importFrom assertthat is.string
#' @importFrom assertthat is.flag
#' @importFrom dplyr db_save_query
#' @importFrom dplyr ident
db_save_query.impala_connection <- function(con, sql, name, temporary = TRUE, external = FALSE,
                                           force = FALSE, analyze = FALSE, ...) {

  # TBD: add params to control external, row format, stored as, location, etc.
  # (or take them in the ... and pass them to db_create_table())

  assert_that(
    is.string(name),
    is.flag(temporary),
    is.flag(external),
    is.flag(force),
    is.flag(analyze)
  )
  if(temporary) {
    stop("Impala does not support temporary tables. Set temporary = FALSE in db_save_query().")
  }

  # too dangerous
  #if(overwrite) {
  #  db_drop_table(con, name, force = TRUE)
  #}

  tt_sql <- build_sql(
    "CREATE ", if (external) sql("EXTERNAL "),
    "TABLE ", ident(name), " ",
    if (force) sql("IF NOT EXISTS "),
    "AS ", sql,
    con = con
  )
  if (analyze) {
    db_analyze(con, name)
  }
  execute_ddl_dml(con, tt_sql)
  name
}


#' @export
#' @importFrom dplyr db_begin
db_begin.impala_connection <- function(con, ...) {
  # do nothing
}

#' @export
#' @importFrom dplyr db_commit
db_commit.impala_connection <- function(con, ...) {
  # do nothing
}

#' @export
#' @importFrom dplyr db_analyze
db_analyze.impala_connection <- function(con, table, ...) {
  sql <- build_sql("COMPUTE STATS", ident(table), con = con)
  execute_ddl_dml(con, sql)
}

#' @export
#' @importFrom dplyr db_drop_table
db_drop_table.impala_connection <- function(con, table, force = FALSE, purge = FALSE, ...) {
  sql <- build_sql(
    "DROP TABLE ", if (force) sql("IF EXISTS "), ident(table), if (purge) sql(" PURGE"),
    con = con
  )
  execute_ddl_dml(con, sql)
}

#' @export
#' @importFrom assertthat assert_that
#' @importFrom assertthat is.string
#' @importFrom assertthat is.flag
#' @importFrom dplyr db_insert_into
#' @importFrom dplyr escape
db_insert_into.impala_connection <- function(con, table, values, overwrite = FALSE, ...) {
  assert_that(
    is.string(table),
    is.data.frame(values),
    is.flag(overwrite)
  )
  if (nrow(values) == 0)
    return(NULL)

  cols <- lapply(values, escape, collapse = NULL, parens = FALSE, con = con)
  col_mat <- matrix(unlist(cols, use.names = FALSE), nrow = nrow(values))

  rows <- apply(col_mat, 1, paste0, collapse = ", ")
  values <- paste0("(", rows, ")", collapse = "\n, ")

  sql <- build_sql(
    "INSERT ",
    if (overwrite) sql("OVERWRITE ") else sql("INTO "),
    ident(table),
    " VALUES ",
    sql(values),
    con = con
  )
  execute_ddl_dml(con, sql)
}

#' @export
#' @importFrom dplyr db_data_type
db_data_type.impala_connection <- function(con, fields, ...) {
  data_type <- function(x) {
    switch(
      class(x)[1],
      logical =   "boolean",
      integer =   "int",
      numeric =   "double",
      factor =    "string",
      character = "string",
      Date =      "timestamp",
      POSIXct =   "timestamp",
      stop("Unknown class ", paste(class(x), collapse = "/"), call. = FALSE)
    )
  }
  vapply(fields, data_type, FUN.VALUE = character(1))
}

#' @export
#' @importFrom assertthat assert_that
#' @importFrom assertthat is.string
#' @importFrom assertthat is.flag
#' @importFrom dplyr db_create_table
#' @importFrom dplyr escape
#' @importFrom dplyr ident
#' @importFrom dplyr sql_vector
db_create_table.impala_connection <- function (con, table, types, temporary = FALSE,
                                              external = FALSE, force = FALSE, ...) {
  # TBD: add params to control external, row format, stored as, location, etc.

  assert_that(
    is.string(table),
    is.character(types),
    is.flag(temporary)
   )
  if(temporary) {
    stop("Impala does not support temporary tables. Set temporary = FALSE in db_create_table().")
  }
  field_names <- escape(ident(names(types)), collapse = NULL, con = con)
  fields <- sql_vector(
    paste0(field_names, " ", types),
    parens = TRUE,
    collapse = ", ",
    con = con
  )
  sql <- build_sql(
    "CREATE ",
    if (external) sql("EXTERNAL "),
    "TABLE ", ident(table), " ",
    if (force) sql("IF NOT EXISTS "),
    fields,
    con = con
  )
  execute_ddl_dml(con, sql)
}

con_acquire <- function (src) {
  con <- src$con
  if (is.null(con)) {
    stop("No connection found", call. = FALSE)
  }
  con
}
# TBD: after new release of dplyr, change this to:
# @export
# @importFrom dplyr con_acquire
# con_acquire.src_impala <- ...

con_release.src_impala <- function(src, con) {
  # do nothing
}
# TBD: after new release of dplyr, change this to:
# @export
# @importFrom dplyr con_release
# con_release.src_impala <- ...


#' @export
#' @importFrom DBI dbGetQuery
setMethod("dbGetQuery", c("src_impala", "character"), function(conn, statement, ...) {
  dbGetQuery(con_acquire(conn), statement)
})

#' @export
#' @importFrom DBI dbDisconnect
setMethod("dbDisconnect", "src_impala", function(conn, ...) {
  dbDisconnect(con_acquire(conn))
})

# Executes a DDL or DML statement
#' @importFrom DBI dbExecute
#' @importFrom utils getFromNamespace
execute_ddl_dml <- function(con, statement) {
  if(inherits(con, "JDBCConnection")) {
    getFromNamespace("dbSendUpdate", "RJDBC")(con, statement)
  } else {
    dbExecute(con, statement)
  }
}

# Escape quotes with a backslash instead of doubling
sql_quote <- function(x, quote) {
  y <- gsub(quote, paste0("\\", quote), x, fixed = TRUE)
  y <- paste0(quote, y, quote)
  y[is.na(x)] <- "NULL"
  names(y) <- names(x)
  y
}

# Gets the dots after a JDBCDriver as a named list, omitting password
getNamedArgs_JDBCDriver <-
  function(url, user = "", password = "", ...) {
    list(url = url, user = user, ...)
  }

# Gets the dots after am OdbcDriver as a named list, omitting pwd
getNamedArgs_OdbcDriver <-
  function(dsn = NULL, ..., timezone = "UTC", driver = NULL, server = NULL,
           database = NULL, uid = NULL, pwd = NULL, .connection_string = NULL) {
    list(dsn = dsn, ..., timezone = timezone, driver = driver,
         server = server, database = database, uid = uid,
         .connection_string = .connection_string)
  }

# Creates an environment that disconnects the database when it's GC'd
db_disconnector <- function(con, quiet = FALSE) {
  reg.finalizer(environment(), function(...) {
    if (!quiet) {
      message("Auto-disconnecting ", class(con)[[1]])
    }
    dbDisconnect(con)
  })
  environment()
}

`%||%` <- function(x, y) if(is.null(x)) y else x