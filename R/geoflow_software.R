#' geoflow_software
#'
#' @docType class
#' @importFrom R6 R6Class
#' @export
#' 
#' @name geoflow_software
#' @title Geoflow software class
#' @description This class models a software to be used by geoflow
#' @keywords software
#' @return Object of \code{\link{R6Class}} for modelling a software
#' @format \code{\link{R6Class}} object.
#' 
#' @examples
#' \dontrun{
#'   software<- geoflow_software$new(
#'    id = "some-id",
#'    type = "output",
#'    software_type = "software",
#'    definition = "definition",
#'    packages = list(),
#'    handler = function(){},
#'    arguments = list(
#'      url = list(def = "the software url")
#'    ),
#'    attributes = list(
#'      workspace = list(def = "a workspace name in the software")
#'    )
#'  )
#' }
#' 
#' @section Methods:
#' \describe{
#'  \item{\code{new(id, type, software_type, definition, handler, arguments, attributes)}}{
#'    This method is used to instantiate a geoflow_software object
#'  }
#'  \item{\code{setId(id)}}{
#'    Set id
#'  }
#'  \item{\code{setType(type)}}{
#'    Set type, a value of class \code{character} "input" or "output"
#'  }
#'  \item{\code{setSoftwareType(software_type)}}{
#'    Set software type
#'  }
#'  \item{\code{setDefinition(definition)}}{
#'    Set definition
#'  }
#'  \item{\code{setAttributes(attributes)}}{
#'    Set attributes
#'  }
#'  \item{\code{setProperties(...)}}{
#'    Set properties. Function called when setting the software properties
#'    from the geoflow configuration.
#'  }
#'  \item{\code{setArguments(arguments)}}{
#'    Set arguments
#'  }
#'  \item{\code{setParameters(...)}}{
#'    Set parameters. Function called when setting the software parameters
#'    from the geoflow configuration.
#'  }
#'  \item{\code{setHandler(handler)}}{
#'    Set handler (a function)
#'  }
#'  \item{\code{checkPackages()}}{
#'    Check that all packages required for the software are available, if yes,
#'    import them in the R session, and return a \code{data.frame} giving the 
#'    packages names and version. If one or more packages are unavailable,
#'    an error is thrown and user informed of the missing packages.
#'  }
#'  \item{\code{getHandlerInstance()}}{
#'    Get an instance of the handler
#'  }
#' }
#' 
#' @author Emmanuel Blondel <emmanuel.blondel1@@gmail.com>
#'
geoflow_software <- R6Class("geoflow_software",
  inherit = geoflowLogger,
  public = list(
    id = NULL,
    type = NULL,
    software_type = NULL,
    definition = NULL,
    packages = list(),
    handler = NULL,
    arguments = list(),
    parameters = list(),
    attributes = list(),
    properties = list(),
    actions = list(),
    initialize = function(id = NULL, type = NULL, software_type, 
                          packages = list(), definition, handler, 
                          arguments, attributes = list(),
                          actions = list()){
      self$setId(id)
      if(!is.null(type)) self$setType(type)
      self$setSoftwareType(software_type)
      self$setPackages(packages)
      self$setDefinition(definition)
      self$setHandler(handler)
      self$setArguments(arguments)
      self$setAttributes(attributes)
      self$setActions(actions)
    },
    
    #setId
    setId = function(id){
      self$id <- id
    },
    
    #setType
    setType = function(type){
      if(!(type %in% c("input","output"))){
        stop("The type should be either an 'input' or 'output'!")
      }
      self$type <- type
    },
    
    #setSoftwareType
    setSoftwareType = function(software_type){
      self$software_type <- software_type
    },
    
    #setPackages
    setPackages = function(packages){
      self$packages <- packages
    },
    
    #setDefinition
    setDefinition = function(definition){
      self$definition <- definition
    },
    
    #setAttributes
    setAttributes = function(attributes){
      self$attributes <- attributes
    },
    
    #setProperties
    setProperties = function(...){
      props <- list(...)[[1]]
      propNames <- names(props)
      if(length(propNames)>0){
        for(propName in propNames){
          if(!(propName %in% names(self$properties))){
            stop(sprintf("The property '%s' is not a valid property for software '%s'. The parameter should be among values [%s]. To see a comprehensive properties list, use the following the code: list_software_properties(\"%s\")",
                         paramName, self$software_type, paste(names(self$attributes), collapse=","), self$software_type))
          }
          self$properties[[propName]] <- props[[propName]]
        }
      }
    },
    
    #setArguments
    setArguments = function(arguments){
      self$arguments <- arguments
    },
    
    #setParameters
    setParameters = function(...){
      params <- list(...)[[1]]
      paramNames <- names(params)
      if(length(paramNames)>0){
        for(paramName in paramNames){
          if(!(paramName %in% names(self$arguments))){
            stop(sprintf("The parameter '%s' is not a valid parameter for software '%s'. The parameter should be among values [%s]. To see a comprehensive parameters list, use the following the code: list_software_parameters(\"%s\")", 
                         paramName, self$software_type, paste(names(self$arguments), collapse=","), self$software_type))
          }
          self$parameters[[paramName]] <- params[[paramName]]
        }
      }
    },
    
    #setActions
    setActions = function(actions){
      self$actions <- actions
    },
    
    #setHandler
    setHandler = function(handler){
      self$handler <- handler
    },
    
    #checkPackages
    checkPackages = function(){
      self$INFO(sprintf("Check package dependencies for software '%s' (%s)", self$id, self$software_type))
      out_pkgs <- try(check_packages(self$packages))
      if(class(out_pkgs)=="try-error"){
        errMsg <- sprintf("One or more packages are not imported although required for software '%s' (%s)", 
                          self$id, self$software_type)
        self$ERROR(errMsg)
        stop(errMsg)
      }else{
        if(is.null(out_pkgs)){
          self$INFO(sprintf("No additional package required for software '%s' (%s):", 
                            self$id, self$software_type))
        }else{
          self$INFO(sprintf("The following packages have been imported for software '%s' (%s):", 
                            self$id, self$software_type))
          print(out_pkgs)
        }
      }
    },
    
    #getHandlerInstance
    getHandlerInstance = function(){
      
      #get handler
      handler_params = paste(sapply(names(self$parameters), function(paramName){
        paramValue <- self$parameters[[paramName]]
        if(is.character(paramValue)) paramValue <- paste0("\"",paramValue,"\"")
        #manage argument handler (if defined)
        argIdx = which(paramName == names(self$arguments))
        if(length(argIdx)>0){
          if(!is.null(self$arguments[[argIdx]]$handler)){
            paramValue <- paste0("self$arguments[[",argIdx,"]]$handler", "(", paramValue, ")")
          }
        }
        return(paste(paramName," = ",paramValue))
      }),collapse=", ")
      instance <- eval(parse(text=paste0("self$handler(",handler_params,")")))
      return(instance)
    }
    
  )
)

#' @name register_software
#' @aliases register_software
#' @title register_software
#' @description \code{register_software} registers default geoflow software
#'
#' @usage register_software()
#' 
#' @note Function called on load by geoflow
#' 
#' @author Emmanuel Blondel, \email{emmanuel.blondel1@@gmail.com}
#' @export
#'
register_software <- function(){
  
  software <- list(
    
    #-------------------------------------------------------------------------------------------------------
    #DBI
    #-------------------------------------------------------------------------------------------------------
    geoflow_software$new(
      software_type = "dbi",
      definition = "Data Base Interface powered by 'DBI' package",
      packages = list("DBI", "RSQLite", "RPostgres"),
      handler = try(DBI::dbConnect, silent = TRUE),
      arguments = list(
        drv = list(def = "DBI driver name", handler = try(DBI::dbDriver, silent = TRUE)),
        user = list(def = "Username"),
        password = list(def = "Password"),
        host = list(def = "Hostname"),
        port = list(def = "Port number"),
        dbname = list(def = "Database name")
      ),
      attributes = list(
        onstart_sql = list(def = "An SQL script to be run on workflow start"),
        onstart_r = list(def = "R instructions to generate a SQL. It should be made of 2 properties 'script' (name
                         of the R script) that should include a function standardized with parameter config (being the
                         DBI software config) and will outpout a character representing the SQL. The name of the function 
                         is to specify in 'fun' property")
      ),
      actions = list(
        onstart = function(config, software, software_config){
          if(!is.null(software_config$properties$onstart_sql) || !is.null(software_config$properties$onstart_r)){
            config$logger.info(sprintf("DBI [id='%s'] Execute 'onstart' action",software_config$id))
            
            sql <- NULL
            if(!is.null(software_config$properties$onstart_sql)){
              config$logger.info(sprintf("SQL script = %s", software_config$properties$onstart_sql))
              sql <- paste0(readLines(software_config$properties$onstart_sql),collapse="\n")
              
            }else if(!is.null(software_config$properties$onstart_r)){
              if(is.null(software_config$properties$onstart_r$script)){
                errMsg <- sprintf("DBI [id='%s'] Error to init 'onstart' from R - Missing 'script'",software_config$id)
                config$logger.error(errMsg)
                stop(errMsg)
              }
              if(is.null(software_config$properties$onstart_r$fun)){
                errMsg <- sprintf("DBI [id='%s'] Error to init 'onstart' from R - Missing 'fun'",software_config$id)
                config$logger.error(errMsg)
                stop(errMsg)
              }
              src <- try(source(software_config$properties$onstart_r$script))
              if(class(src)=="try-error"){
                errMsg <- sprintf("DBI [id='%s'] Error to init 'onstart' from R - Error while sourcing script '%s'",
                                  software_config$id, software_config$properties$onstart_r$script)
                config$logger.error(errMsg)
                stop(errMsg)
              }
              onstart_r_fun <- eval(parse(text=software_config$properties$onstart_r$fun))
              print(class(onstart_r_fun))
              sql <- try(onstart_r_fun(config, software, software_config))
              if(class(sql)=="try-error"){
                errMsg <- sprintf("DBI [id='%s'] Error to init 'onstart' from R - Error while executing function '%s'",
                                  software_config$id, software_config$properties$onstart_r$fun)
                config$logger.error(errMsg)
                stop(errMsg)
              }
            }
            config$logger.info(sprintf("DBI [id='%s'] Executing SQL",software_config$id))
            config$logger.info(paste0("\n", sql))
            
            #write sql to file
            if (!dir.exists("sql")){
              config$logger.info(sprintf("Creating 'sql' directory: %s", file.path(getwd(), "sql")))
              dir.create(file.path(getwd(), "sql"))
            }
            sqlfilename <- paste0(software_config$id, "_onstart.sql")
            config$logger.info(sprintf("DBI [id='%s'] Writing SQL file '%s' to job directory",software_config$id, sqlfilename))
            writeChar(sql, file.path(getwd(), "sql", sqlfilename), eos = NULL)
            
            #send sql to dB
            out <- try(DBI::dbSendQuery(software, sql))
            if(class(out)=="try-error"){
              errMsg <- sprintf("DBI [id='%s'] Error while executing SQL",software_config$id)
              config$logger.error(errMsg)
              stop(errMsg)
            }
            config$logger.info(sprintf("DBI [id='%s'] Successful SQL execution!",software_config$id))
          }else{
            config$logger.info(sprintf("DBI [id='%s'] No 'sqlonstart' property. Skipping 'onstart' action",software_config$id))
          }
        }
      )
    ),
    #-------------------------------------------------------------------------------------------------------
    #GOOGLE DRIVE
    #-------------------------------------------------------------------------------------------------------    
    geoflow_software$new(
      software_type = "googledrive",
      definition = "Google Drive access powered by 'googledrive' package",
      packages = list("gsheet"),
      handler = try(googledrive::drive_auth, silent = TRUE),
      arguments = list(
        email = list(def = "User email to authenticate in Google Drive"),
        path = list(def = "An optional path within the Google drive repository. Default will be the root"),
        token = list(def = "The user authentication token. To get your token in R: gargle::token_fetch()$credentials$access_token")
      )
    ),
    #-------------------------------------------------------------------------------------------------------
    #OGC WFS
    #-------------------------------------------------------------------------------------------------------
    geoflow_software$new(
      software_type = "csw",
      definition = "OGC Catalogue Service for the Web (CSW) client powered by 'ows4R' package",
      packages = list("ows4R"),
      handler = try(ows4R::CSWClient$new, silent = TRUE),
      arguments = list(
        url = list(def = "CSW service endpoint URL"),
        serviceVersion = list(def = "CSW service version ('2.0.2' or '3.0')"),
        user = list(def = "Username for CSW authentication"),
        pwd = list(def = "Password for CSW authentication"),
        logger = list(def = "Level for 'ows4R' logger messages (NULL,INFO or DEBUG)")
      )
    ),
    #-------------------------------------------------------------------------------------------------------
    #OGC WFS
    #-------------------------------------------------------------------------------------------------------
    geoflow_software$new(
      software_type = "wfs",
      definition = "OGC Web Feature Service (WFS) client powered by 'ows4R' package",
      packages = list("ows4R"),
      handler = try(ows4R::WFSClient$new, silent = TRUE),
      arguments = list(
        url = list(def = "WFS service endpoint URL"),
        serviceVersion = list(def = "WFS service version ('1.0.0', '1.1.1', '2.0')"),
        user = list(def = "Username for WFS authentication"),
        pwd = list(def = "Password for WFS authentication"),
        logger = list(def = "Level for 'ows4R' logger messages (NULL, 'INFO' or 'DEBUG')")
      )
    ),
    #-------------------------------------------------------------------------------------------------------
    #GEONETWORK API
    #-------------------------------------------------------------------------------------------------------
    geoflow_software$new(
      software_type = "geonetwork",
      definition = "GeoNetwork API Client, powered by 'geonapi' package",
      packages = list("geonapi"),
      handler = try(geonapi::GNManager$new, silent = TRUE),
      arguments = list(
        url = list(def = "GeoNetwork catalogue URL"),
        version = list(def = "Geonetwork catalogue version"),
        user = list(def = "Username for GeoNetwork authentication"),
        pwd = list(def = "Password for GeoNetwork authentication"),
        logger = list(def = "Level for 'geonapi' logger messages (NULL, 'INFO' or 'DEBUG')")
      )
    ),
    #-------------------------------------------------------------------------------------------------------
    #GEOSERVER API
    #-------------------------------------------------------------------------------------------------------
    geoflow_software$new(
      software_type = "geoserver",
      definition = "GeoServer REST API Client, powered by 'geosapi' package",
      packages = list("geosapi"),
      handler = try(geosapi::GSManager$new, silent = TRUE),
      arguments = list(
        url = list(def = "GeoServer application URL"),
        user = list(def = "Username for GeoServer authentication"),
        pwd = list(def = "Password for GeoServer authentication"),
        logger = list(def = "Level for 'geosapi' logger messages (NULL, 'INFO' or 'DEBUG')")    
      ),
      attributes = list(
        workspace = list(def = "GeoServer workspace name"),
        datastore = list(def = "GeoServer datastore name")
      ),
      actions = list(
        onstart = function(config, software, software_config){
          config$logger.info("Executing GeoServer 'onstart' action")
          if(!is.null(config$properties$workspace)){
            ws <- software$getWorkspace(config$properties$workspace)
            if(is.null(ws)){
              software$createWorkspace(config$properties$workspace, paste0("http://",config$properties$workspace))
            }
          }
          #TODO to be completed with datastore creation cases
        },
        onend = function(config, software, software_config){
          config$logger.info("Executing GeoServer 'onend' action")
          software$reload()
        }
      )
    ),
    #-------------------------------------------------------------------------------------------------------
    #ZENODO
    #-------------------------------------------------------------------------------------------------------
    geoflow_software$new(
      software_type = "zenodo",
      definition = "Zenodo client powered by 'zen4R' package",
      packages = list("zen4R"),
      handler = try(zen4R::ZenodoManager$new, silent = TRUE),
      arguments = list(
        url = list(def = "Zenodo API URL. For sandbox tests, use 'https://sandbox.zenodo.org/api', otherwise provided by zen4R by default"),
        token = list(def = "Zenodo user authentication token."),
        logger = list(def = "Level for 'zen4R' logger messages (NULL, 'INFO' or 'DEBUG')")
      ),
      attributes = list(
        clean = list(def = "An option, to clean draft Zenodo deposits prior to any new deposit. To clean deposits, enable 'run', 
                     and optionally specify either a 'query' (ElasticSearch Zenodo query), a list of 'doi', or 'community' for which
                     you want to restrain the cleaning operation.")
      )
    ),
    #-------------------------------------------------------------------------------------------------------
    #DATAVERSE SWORD CLIENT
    #-------------------------------------------------------------------------------------------------------
    geoflow_software$new(
      software_type = "sword_for_dataverse",
      definition = "Dataverse SWORD API Client powered by 'atom4R' package",
      packages = list("atom4R"),
      handler = try(atom4R::SwordDataverseClient$new, silent = TRUE),
      arguments = list(
        hostname = list(def = "Dataverse base URL"),
        token = list(def = "Dataverse user authentication token"),
        logger = list(def = "Level for 'atom4R' logger messages (NULL, 'INFO' or 'DEBUG')")
      ),
      attributes = list(
        dataverse = list(def = "Dataverse id where to deposit/publish records")
      )
    ),
    #-------------------------------------------------------------------------------------------------------
    #DATAONE CLIENT
    #-------------------------------------------------------------------------------------------------------
    geoflow_software$new(
      software_type = "dataone",
      definition = "DataONe API Client powered by 'dataone' package",
      packages = list("dataone"),
      handler = try(dataone::D1Client, silent = TRUE),
      arguments = list(
        x = list(def = "Contributing Node URL", handler = try(dataone::CNode, silent = TRUE)),
        y = list(def = "Member Node URL", handler = try(dataone::MNode, silent = TRUE)),
        token = list(def = "Authorization token")
      ),
      attributes = list(),
      actions = list(
        onstart = function(config, software, software_config){
          config$logger.info("Executing DataOne 'onstart' action")
          options(dataone_test_token = software_config$parameters$token)
          options(dataone_token = software_config$parameters$token)
        },
        onend = function(config, software, software_config){
          config$logger.info("Executing DataOne 'onend' action")
          options(dataone_test_token = NULL)
          options(dataone_token = NULL)
        }
      )
    )
    
  )
  .geoflow$software <- software
}

#' @name list_software
#' @aliases list_software
#' @title list_software
#' @description \code{list_software} lists the software supported by geoflow.
#'
#' @usage list_software(raw)
#' 
#' @param raw Default value is \code{FALSE}, meaning the software will be listed as
#' \code{data.frame}. The output If \code{TRUE} the raw list of \link{geoflow_software} 
#' is returned.
#' 
#' @return an object of class \code{data.frame} (or \code{list} of \link{geoflow_software} if raw = FALSE)
#' 
#' @author Emmanuel Blondel, \email{emmanuel.blondel1@@gmail.com}
#' @export
#'
list_software <- function(raw = FALSE){
  software <- .geoflow$software
  if(raw){
    return(software)
  }else{
    software <- do.call("rbind", lapply(software, function(obj){
      obj.out <- data.frame(
        software_type = obj$software_type,
        definition = obj$definition,
        packages = paste(obj$packages, collapse=","),
        stringsAsFactors = FALSE
      )
      return(obj.out)
    }))
  }
  return(software)
}

#' @name list_software_parameters
#' @aliases list_software_parameters
#' @title list_software_parameters
#' @description \code{list_software_parameters} lists the parameters of a given software supported by geoflow.
#'
#' @usage list_software_parameters(software_type)
#' 
#' @param software_type A software type
#' 
#' @return an object of class \code{data.frame} listing the software parameters
#' 
#' @author Emmanuel Blondel, \email{emmanuel.blondel1@@gmail.com}
#' @export
#'
list_software_parameters <- function(software_type){
  out <- NULL
  software <- .geoflow$software[sapply(.geoflow$software, function(x){x$software_type == software_type})]
  if(length(software)==0) stop(sprintf("No software '%s'!", software_type))
  software <- software[[1]]
  if(length(software$arguments)>0){
    out <- data.frame(
      name = names(software$arguments),
      definition = sapply(software$arguments, function(x){x$def}),
      stringsAsFactors = FALSE
    )
    row.names(out) <- 1:nrow(out)
  }else{
    out <- data.frame(name = character(0), definition = character(0))
  }
  return(out)
}

#' @name list_software_properties
#' @aliases list_software_properties
#' @title list_software_properties
#' @description \code{list_software_properties} lists the properties of a given software supported by geoflow.
#'
#' @usage list_software_properties(software_type)
#' 
#' @param software_type A software type
#' 
#' @return an object of class \code{data.frame} listing the software properties
#' 
#' @author Emmanuel Blondel, \email{emmanuel.blondel1@@gmail.com}
#' @export
#'
list_software_properties <- function(software_type){
  out <- NULL
  software <- .geoflow$software[sapply(.geoflow$software, function(x){x$software_type == software_type})]
  if(length(software)==0) stop(sprintf("No software '%s'!", software_type))
  software <- software[[1]]
  if(length(software$attributes)>0){
    out <- data.frame(
      name = names(software$attributes),
      definition = sapply(software$attributes, function(x){x$def}),
      stringsAsFactors = FALSE
    )
    row.names(out) <- 1:nrow(out)
  }else{
    out <- data.frame(name = character(0), definition = character(0))
  }
  return(out)
}
