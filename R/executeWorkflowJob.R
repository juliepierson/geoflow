#' @name executeWorkflowJob
#' @aliases executeWorkflowJob
#' @title executeWorkflowJob
#' @description \code{executeWorkflowJob} allows to execute a workflow job
#'
#' @usage executeWorkflowJob(config, jobdir)
#'                 
#' @param config a configuration object as read by \code{initWorkflow}
#' @param jobdir the Job directory. Optional, by default inherited with the configuration.
#' 
#' @author Emmanuel Blondel, \email{emmanuel.blondel1@@gmail.com}
#' @export
#'    
executeWorkflowJob <- function(config, jobdir = NULL){
  
    if(is.null(jobdir)) jobdir <- config$job
  
    config$logger.info("Executing workflow job...")
    
    #options
    skipFileDownload <- if(!is.null(config$options$skipFileDownload)) config$options$skipFileDownload else FALSE
  
    #Actions onstart
    config$logger.info("---------------------------------------------------------------------------------------")
    config$logger.info("Executing software actions 'onstart' ...")
    
    #function to run software actions
    runSoftwareActions <- function(config, softwareType, actionType){
      software_list <- config$software[[softwareType]]
      if(length(software_list)>0){
        software_names <- names(software_list)
        software_names <- software_names[!endsWith(software_names, "_config")]
        for(software_name in software_names){
          software <- software_list[[software_name]]
          software_cfg <- software_list[[paste0(software_name, "_config")]]
          if(length(software_cfg$actions)>0){
            if(actionType %in% names(software_cfg$actions)){
              config$logger.info(sprintf("Executing input software action '%s'",actionType))
              software_cfg$actions[[actionType]](config, software, software_cfg)
            }
          }
        }
      }
    }
    #run software 'onstart' actions
    runSoftwareActions(config, "input", "onstart")
    runSoftwareActions(config, "output", "onstart")
    
    #workflow actions
    config$logger.info("---------------------------------------------------------------------------------------")
    config$logger.info("Executing entity actions ...")
    actions <- config$actions
    if(is.null(actions)){
      config$logger.warn("No actions enabled for this workflow!")
    }else{
      if(length(actions)==0){
        config$logger.warn("No actions enabled for this workflow!")
      }else{
        config$logger.info(sprintf("Workflow mode: %s", config$mode))
        config$logger.info(sprintf("Workflow with %s actions", length(actions)))
        for(i in 1:length(actions)){config$logger.info(sprintf("Action %s: %s", i, actions[[i]]$id))}
      }
    }
    
    if(config$mode == "entity"){
     
      #execute entity-based actions
      entities <- config$metadata$content$entities
      if(!is.null(entities)){
        
        #inspect if there are DOI-management related actions
        withZenodo <- any(sapply(actions, function(x){x$id=="zen4R-deposit-record"}))
        withDataverse <- any(sapply(actions, function(x){x$id=="atom4R-dataverse-deposit-record"}))
        
        #cleaning in case Zenodo action is enabled with clean properties 
        if(withZenodo){
          ZENODO_CONFIG <- config$software$output$zenodo_config
          clean <- ZENODO_CONFIG$properties$clean
          if(!is.null(clean)) if(!is.null(clean$run)) if(as.logical(clean$run)){
            config$logger.info("Zenodo action 'clean' activated: deleting deposits prior to new deposits!")
            if(is.null(clean$query) 
               & length(clean$doi)==0 
               & length(clean$community)==0){
              config$logger.info("Zenodo: no query or list of DOIs specified for cleaning: cleaning all draft deposits")
              config$software$output$zenodo$deleteRecords()
            }else{
              #selective cleaning by Zenodo ElasticSearch query
              if(!is.null(clean$query)){
                config$logger.info(sprintf("Zenodo: cleaning draft deposits based on query '%s'",clean$query))
                config$software$output$zenodo$deleteRecords(q = clean$query)
              }
              #selective cleaning by prereserved DOI(s)
              if(!is.null(clean$doi)){
                config$logger.info(sprintf("Zenodo: cleaning draft deposits with prereserved DOIs [%s]", paste(clean$doi, collapse=",")))
                invisible(lapply(clean$doi, config$software$output$zenodo$deleteRecordByDOI))
              }
              #selective cleaning by community(ies)
              if(!is.null(clean$community)){
                config$logger.info(sprintf("Zenodo: cleaning draft deposits in communities [%s]", paste(clean$community, collapse=",")))
                invisible(lapply(clean$community, function(community){
                  config$software$output$zenodo$deleteRecords(q = sprintf("communities:%s", community))
                }))
              }
            }
            config$logger.info("Zenodo: sleeping 5 seconds...")
            Sys.sleep(5)    
          }
        }
        
        for(entity in entities){
          
          #enrich metadata with dynamic properties
          if(!is.null(entity$data)){
            #data features
            entity$enrichWithFeatures(config)
            #data relations (eg. geosapi & OGC data protocol online resources)
            entity$enrichWithRelations(config)
          }
          
          #enrich entities with metadata (other properties)
          entity$enrichWithMetadata(config)
          
          #if entity has data we copy data to job data dir
          if(!is.null(entity$data) & !skipFileDownload) entity$copyDataToJobDir(config, jobdir)
          
          #run sequence of entity data actions (if any)
          if(!is.null(entity$data)) {
            if(entity$data$run){
              if(length(entity$data$actions)>0){
                for(i in 1:length(entity$data$actions)){
                  entity_action <- entity$data$actions[[i]]
                  config$logger.info(sprintf("Executing entity data action %s: '%s' ('%s')", i, entity_action$id, entity_action$script))
                  entity_action$fun(entity, config, entity_action$options)
                }
                #we trigger entity enrichment (in case entity data action involved modification of entity)
                entity$enrichWithMetadata()
              }
            }else{
              config$logger.info("Execution of entity data actions is disabled")
            }
          }
          
          #run sequence of global actions
          if(length(actions)>0) for(i in 1:length(actions)){
            action <- actions[[i]]
            config$logger.info(sprintf("Executing Action %s: %s - for entity %s", i, action$id, entity$identifiers[["id"]]))
            action$fun(entity = entity, config = config, options = action$options)
          }
          #if zenodo is among actions, file upload (and possibly publish) to be managed here
          if(withZenodo){
            #if Zenodo is the only action then let's sleep to avoid latence issues when listing depositions
            #if no sleep is specified, getDepositions doesn't list yet the newly deposited recorded with
            #isIdenticalTo relationship
            if(length(actions)==1){
              config$logger.info("Zenodo: sleeping 5 seconds...")
              Sys.sleep(5)
            }
            zen_action <- actions[sapply(actions, function(x){x$id=="zen4R-deposit-record"})][[1]]
            act_options <- zen_action$options
            act_options$depositWithFiles <- TRUE
            zen_action$fun(entity, config, act_options)
          }
          
          #if atom4R/dataverse is among actions, file upload (and possibly publish) to be managed here
          if(withDataverse){
            dv_action <- actions[sapply(actions, function(x){x$id=="atom4R-dataverse-deposit-record"})][[1]]
            act_options <- dv_action$options
            act_options$depositWithFiles <- TRUE
            dv_action$fun(entity, config, act_options)
          }
          
          entity$data$features <- NULL
        }
        
        #special business logics in case of DOI management
        #in case Zenodo or Dataverse was enabled, we create an output table of DOIs & export altered source entities
        ##ZENODO
        if(withZenodo){
          config$logger.info("Exporting reference list of Zenodo DOIs to job directory")
          out_zenodo_dois <- do.call("rbind", lapply(entities, function(entity){
            return(data.frame(
              Identifier = entity$identifiers[["id"]], 
              Status = entity$status$zenodo,
              DOI_for_allversions = entity$identifiers[["zenodo_conceptdoi_to_save"]],
              DOI_for_version = entity$identifiers[["zenodo_doi_to_save"]],
              stringsAsFactors = FALSE
            ))
          }))
          readr::write_csv(out_zenodo_dois, file.path(getwd(),"metadata", "zenodo_dois.csv"))
      
          config$logger.info("Exporting source entities table enriched with DOIs")
          src_entities <- config$src_entities
          src_entities$Identifier <- sapply(1:nrow(src_entities), function(i){
            identifier <- src_entities[i, "Identifier"]
            if(!endsWith(identifier, .geoflow$LINE_SEPARATOR)) identifier <- paste0(identifier, .geoflow$LINE_SEPARATOR)
            if(regexpr("doi", identifier)>0) return(identifier)
            if(out_zenodo_dois[i,"Status"] == "published") return(identifier)
            identifier <- paste0(identifier, "doi:", out_zenodo_dois[i,"DOI_for_allversions"])
            return(identifier)
          })
          readr::write_csv(src_entities, file.path(getwd(),"metadata","zenodo_entities_with_doi_for_publication.csv"))

          
          config$logger.info("Exporting workflow configuration for Zenodo DOI publication")
          src_config <- config$src_config
          
          #modifying handler to csv/exported table - to see with @juldebar
          src_config$metadata$entities$handler <- "csv"
          src_config$metadata$entities$source <- "zenodo_entities_with_doi_for_publication.csv"
          
          #altering clean property
          #deactivated for the timebeing, quite dangerous, to discuss with @juldebar
          #zen_software <- src_config$software[sapply(src_config$software, function(x){x$software_type == "zenodo"})][[1]]
          #zen_clean <- if(!is.null(zen_software$properties$clean$run)) zen_software$properties$clean$run else FALSE
          #invisible(lapply(1:length(src_config$software), function(i){
          #  software <- src_config$software[[i]]
          #  if(software$software_type=="zenodo"){
          #    src_config$software[[i]]$properties$clean$run <<- if(zen_clean) FALSE else TRUE
          #  }
          #}))
          
          #altering publish option
          zen_action <- src_config$actions[sapply(src_config$actions, function(x){x$id=="zen4R-deposit-record"})][[1]]
          zen_publish <- if(!is.null(zen_action$options$publish)) zen_action$options$publish else FALSE
          invisible(lapply(1:length(src_config$actions), function(i){
            action <- src_config$actions[[i]]
            if(action$id=="zen4R-deposit-record"){
              src_config$actions[[i]]$options$publish <<- if(zen_publish) FALSE else TRUE
            }
          }))
          #export modified config
          jsonlite::write_json(
            src_config, file.path(getwd(),"metadata","zenodo_geoflow_config_for_publication.json"),
            auto_unbox = TRUE, pretty = TRUE
          )
          
          #modifying global option
          src_config$options$skipFileDownload <- if(zen_publish) FALSE else TRUE
          
        }
        
        #DATAVERSE
        if(withDataverse){
          config$logger.info("Exporting reference list of Dataverse DOIs to job directory")
          out_dataverse_dois <- do.call("rbind", lapply(entities, function(entity){
            return(data.frame(
              Identifier = entity$identifiers[["id"]], 
              Status = entity$status$dataverse,
              DOI_for_allversions = entity$identifiers[["dataverse_conceptdoi_to_save"]],
              DOI_for_version = entity$identifiers[["dataverse_doi_to_save"]],
              stringsAsFactors = FALSE
            ))
          }))
          readr::write_csv(out_dataverse_dois, file.path(getwd(),"metadata", "dataverse_dois.csv"))
          
          config$logger.info("Exporting source entities table enriched with Dataverse DOIs")
          src_entities <- config$src_entities
          src_entities$Identifier <- sapply(1:nrow(src_entities), function(i){
            identifier <- src_entities[i, "Identifier"]
            if(!endsWith(identifier, .geoflow$LINE_SEPARATOR)) identifier <- paste0(identifier, .geoflow$LINE_SEPARATOR)
            if(regexpr("doi", identifier)>0) return(identifier)
            if(out_dataverse_dois[i,"Status"] == "published") return(identifier)
            identifier <- paste0(identifier, "doi:", out_dataverse_dois[i,"DOI_for_allversions"])
            return(identifier)
          })
          readr::write_csv(src_entities, file.path(getwd(),"metadata","dataverse_entities_with_doi_for_publication.csv"))
          
          
          config$logger.info("Exporting workflow configuration for Dataverse DOI publication")
          src_config <- config$src_config
          
          #modifying handler to csv/exported table - to see with @juldebar
          src_config$metadata$entities$handler <- "csv"
          src_config$metadata$entities$source <- "dataverse_entities_with_doi_for_publication.csv"
          
          #altering publish option
          dataverse_action <- src_config$actions[sapply(src_config$actions, function(x){x$id=="atom4R-dataverse-deposit-record"})][[1]]
          dataverse_publish <- if(!is.null(dataverse_action$options$publish)) dataverse_action$options$publish else FALSE
          invisible(lapply(1:length(src_config$actions), function(i){
            action <- src_config$actions[[i]]
            if(action$id=="atom4R-dataverse-deposit-record"){
              src_config$actions[[i]]$options$publish <<- if(dataverse_publish) FALSE else TRUE
            }
          }))
          #export modified config
          jsonlite::write_json(
            src_config, file.path(getwd(),"metadata","dataverse_geoflow_config_for_publication.json"),
            auto_unbox = TRUE, pretty = TRUE
          )
          
          #modifying global option
          src_config$options$skipFileDownload <- if(dataverse_publish) FALSE else TRUE
          
        }
        
        #save entities & contacts used
        readr::write_csv(config$src_entities, file.path(getwd(), "metadata", "config_copyof_entities.csv"))
        readr::write_csv(config$src_contacts, file.path(getwd(), "metadata", "config_copyof_contacts.csv"))
        
      }
    }else if(config$mode == "raw"){
      #execute raw actions (--> not based on metadata entities)
      for(i in 1:length(actions)){
        action <- actions[[i]]
        config$logger.info(sprintf("Executing Action %s: %s", i, action$id))
        eval(expr = parse(action$script))
      }
    }
    
    #Actions onend
    config$logger.info("---------------------------------------------------------------------------------------")
    config$logger.info("Executing software actions 'onend' ...")
    #run software 'onend' actions
    runSoftwareActions(config, "input", "onend")
    runSoftwareActions(config, "output", "onend")
}