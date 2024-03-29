
###NEEDS TO BE RUN ON LAPTOP WHILE ON NAU NETWORK
#####REWRITTEN TO RUN ON OFFICE DESKTOP

#Create generalized function that takes Lat/Long values and outputs predicted BFI
BFI.predictor <- function(input_dataframe, model_path) { #data path contains lat/long points | Model path is the path to the model desired
    # Load necessary libraries
    packages <- c("dplyr", "sf", "raster", "terra", "ggplot2", "readr", "boot", "progress")
    invisible(lapply(packages, library, character.only = TRUE))
    
    # For Repeatability
    setwd("~/GitHub/Base-Flow-Spatial")
    set.seed(313)
    # Load input data
    River_Points <- input_dataframe
    
    year_list <- c(seq(from = 1991, to = 2020))
    River_Points$ID <- 1:nrow(River_Points)
    
    expanded_years <- expand.grid(LAT = unique(River_Points$LAT), YEAR = year_list) #add years to each site
    River_Points <- merge(River_Points,expanded_years, by = "LAT", all.x = TRUE)
    
    River_Points <- River_Points[ order(River_Points$ID, River_Points$YEAR),]
    
    River_Points <- River_Points[,c("ID","YEAR","LAT","LONG")]
    
    colnames(River_Points) <- c("ID","YEAR","LAT","LONG")
    
    
    # Load HUC8 basin raster
    HUC8_Basins <- terra::rast("S:/CEFNS/SESES/GLG/Open/Mroczek,Caelum/Data/HUC8_rasters/huc8.tif")
    HUC8_Basins <- project(HUC8_Basins, "+proj=longlat +datum=WGS84")
    
    
    # Load DEM raster
    DEM <- rast("S:/CEFNS/SESES/GLG/Open/Mroczek,Caelum/Data/DEM_30M/AZ_DEM_30M_latlong.tif")
    #DEM <- project(DEM, "+proj=longlat")
    #writeRaster(DEM,"S:/CEFNS/SESES/GLG/Open/Mroczek,Caelum/Data/DEM_30M/AZ_DEM_30M_latlong.tif") #write lat long projected DEM
    
# Assign HUC8 basin and elevation
    pb <- progress_bar$new(total = nrow(River_Points),
                           format = "[:bar] :percent eta: :eta")
    pb$tick(0)
    for (i in 1:nrow(River_Points)) {
      p <- vect(River_Points[i,], geom = c("LONG", "LAT"))
      huc <- terra::extract(HUC8_Basins, p)
      elev <- terra::extract(DEM, p)
      River_Points$HUC8[i] <- as.numeric(as.character(huc[, 2]))
      River_Points$ELEVATION_FT[i] <- (elev[, 2]) * 3.281
      pb$tick()
    }
    
    River_Points <- na.omit(River_Points)
    #Precip/HUC speadsheet
    precip_df <- read.csv("~/GitHub/Base-Flow-Spatial/Data/HUC_precip.csv")
    et_df <- read.csv("~/GitHub/Base-Flow-Spatial/Data/HUC_annualET.csv")
    
    pb <- progress_bar$new(total = nrow(River_Points),
                           format = "[:bar] :percent eta: :eta")
    pb$tick(0)
    # Assign temperature and precipitation data 
    for (i in 1:nrow(River_Points)) {
      year <- River_Points$YEAR[i]
      whichRaster_T <- paste0("S:/CEFNS/SESES/GLG/Open/Mroczek,Caelum/Data/Temp_PRISM/OutputRasters_HUC/tmp", year, "_huc")
      thisRaster_T <- rast(whichRaster_T)
      whichRaster_P <- paste0("S:/CEFNS/SESES/GLG/Open/Mroczek,Caelum/Data/Precip_PRISM/Output_Rasters_HUC/ppt", year, "_huc")
      thisRaster_P <- rast(whichRaster_P)
      whichYear <- paste0("X", year)
      pptHUC <- which(precip_df$HUC == River_Points$HUC8[i])
      ppt <- precip_df[pptHUC, whichYear]
      
      etHUC <- which(et_df$HUC8 == River_Points$HUC8[i])
      et <- et_df[etHUC, whichYear]
      
      e_T <- terra::extract(thisRaster_T, p)
      #e_P <- terra::extract(thisRaster_P, p)
      River_Points$TEMP_C[i] <- round(e_T[ ,2], 2)
      #River_Points$PRECIP_MM[i] <- round(e_P[, 2], 2)
      River_Points$PRECIP_MM[i] <- round(ppt, 2)

      River_Points$ET_MM[i] <- round(et, 2)
  
      pb$tick()
    }
    
    # Load HUC predictors
    HUC_Predictors <- read_csv("~/GitHub/Base-Flow-Spatial/Data/HUC_Dataset.csv", show_col_types = FALSE)
    
    # Merge dataframes
    RiverPoints_AllData <- merge(River_Points, HUC_Predictors, by = "HUC8", all.x = TRUE)
    RiverPoints_AllData <- RiverPoints_AllData[, -c(10)]
    RiverPoints_AllData <- RiverPoints_AllData[, c(1, 3:51)]
    
    # Load XGBoost model
    xgb_model <- readRDS(model_path)
    feature_names <- xgb_model$feature_names
    RiverPoints_AllData <- RiverPoints_AllData[, c("HUC8", "YEAR", "LAT",  "LONG", feature_names)]
    
  
    # Predict BFI with XGBoost model
    RiverPoints_AllData$predictedBFI <- inv.logit(predict(object = xgb_model, newdata = as.matrix(RiverPoints_AllData[,5:50])))
    
    mean_predictedBFI <- tapply(RiverPoints_AllData$predictedBFI, RiverPoints_AllData$HUC8, mean, na.rm = TRUE)
    
    mean_P <- tapply(RiverPoints_AllData$PRECIP_MM, RiverPoints_AllData$HUC8, mean, na.rm = TRUE)
    
    mean_ET <- tapply(RiverPoints_AllData$ET_MM, RiverPoints_AllData$HUC8, mean, na.rm = TRUE)
    
    # Convert the result to a data frame
    result_df <- data.frame(HUC8 = names(mean_predictedBFI), 
                            mean_predictedBFI = as.numeric(mean_predictedBFI))

  })
    return(RiverPoints_AllData)
}

write.csv(result_df, "~/Documents/GitHub/BFI_Research/Base-Flow-Spatial/Data/HUC_BFI.csv")
