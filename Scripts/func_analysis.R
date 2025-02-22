#=================================================================#
# ========== FUNCTIONAL ANNOTATION AND PATHWAY ANALYSIS ========= =
#=================================================================#
options(connectionObserver = NULL)

source("https://raw.githubusercontent.com/nevelsk90/R_scripts/master/usefulRfunc.r")

library( biomaRt)
library( colorspace )
library( stringr )
library(msigdbr)
library("org.Mm.eg.db")
library(GO.db)
library(DBI)


## load mart objects
mart_mouse <- biomaRt::useMart(biomart = "ENSEMBL_MART_ENSEMBL",dataset = "mmusculus_gene_ensembl")
entr2gName <- getBM( attributes=c('external_gene_name', 
                                  "entrezgene_id" ) ,  mart = mart_mouse)
esmbID2gName <- getBM( attributes=c('ensembl_gene_id', 
                                  "external_gene_name" ) ,  mart = mart_mouse)
esmbID2entr <- getBM( attributes=c('ensembl_gene_id', 
                                  "entrezgene_id" ) ,  mart = mart_mouse )

####======== GO ANALYSIS ===========####
### prepare GO annotations
  {
  #  get all unique genes AND genes of child terms
  go2ensemble <- readRDS( file="hepatocyte-damage-score/Data/Input/FunctionalAnalysis/go2ensemble.rda" )
    
  go2gName  <- readRDS( file="hepatocyte-damage-score/Data/Input/FunctionalAnalysis/go2gName.rda")
  go2gName <- lapply(go2gName, function(X) X[!is.na(X)])
  go2gName <- go2gName[ sapply(go2gName, length)> 0 ]

  library(GO.db)
  goterms <- Term(GOTERM)
  goont <- Ontology(GOTERM)
  
}

################# GO annotation with Robert function ################ #
  {
  ### prepare gene set by annotating ensembleID with entrezID
    options(connectionObserver = NULL)

  source("hepatocyte-damage-score/Data/Input/FunctionalAnalysis/justGO_ROBERT.R")

    
  # # use Robert's function to create sparse binary matrix indicating membership of genes (columns) in GO terms (rows)
  # gomatrix=sf.createGoMatrix()
  # # 31.08.23
  # saveRDS(gomatrix, file="/media/tim_nevelsk/WD_tim/ANNOTATIONS/GO/gomatrix.31.08.23.rda")
    
    gomatrix <- readRDS("hepatocyte-damage-score/Data/Input/FunctionalAnalysis/gomatrix.31.08.23.rda")


}

####======== Prepare Pathways  ========####

pathlist <- readRDS("hepatocyte-damage-score/Data/Input/FunctionalAnalysis/pathDB.rda")


####======== barplots for annotation results ==========
    # clustered barplot for robertGO results     
      GOrobert_barplot_clustered <- function( iid=iids,
                                              GOtoPlot= topN_GOrb,
                                              datGO = GOrobert_res ,
                                              # datLFC = GO_meanLFC ,
                                              datLFC = F ,
                                              datOrder,
                                              scaleLFC=T,
                                              labelTRUNK= 50 )
        {
        ## * iids - a numeric vector, defining which elements of datGO list to plot as columns of the barplot
        ## * GOtoPlot - a charchter vector of GO IDs for which datLFC will be plotted 
        ## * datGO - a list, where each element contains results of Robert's sf.createGoMatrix() funcion
        ## * datLFC - a matrix of mean LFCs (or other measures of GO changes) , if FALSE then log2Enrichment of GO test is used for color
        ## that will be used as a color of bars, if not provided log2FC of enrichment will be used
        ## * oorder - a charachter vector, defining order in which datasets (in columns) appear on the plot
        ## * labelTRUNK - logical or numerical value, if labels should be shorten, to what length
        
        require(colorspace)
        # require(go2gName)
        library(GeneOverlap)
        
        ### cluster terms based on gene set simmilarity
        {
          GOlist <-go2gName[ match( GOtoPlot , names(go2gName) )]
          MM<- GeneOverlap::newGOM( GOlist , GOlist , genome.size=20000) ### set genome size to 10K when used with sc/sn
          MMjcc <- GeneOverlap::getMatrix(MM, name="Jaccard")
          GOid <- colnames( MMjcc )
          rownames( MMjcc ) <- colnames( MMjcc ) <- goterms[ colnames( MMjcc )]
          oorder <- hclust( as.dist(1-MMjcc) , method = "ward.D2")
          
          # prepare for plotting
          toPlot <- MMjcc
          toPlot <- reshape2::melt(toPlot)
          toPlot$ontology <- goont[ GOid ]
          toPlot$yaxis_full <- toPlot$Var1
          
          # concatenate labels and order rows/columns by gene set simmilarity
          toPlot$Var1 <- factor(   sapply( as.character(toPlot$Var1)  , str_trunc, labelTRUNK) , 
                                   levels =  sapply( oorder$labels[oorder$order] , str_trunc, labelTRUNK) )
          toPlot$Var2 <- factor(toPlot$Var2, levels = oorder$labels[oorder$order] )
          
          # plot ontology
          gg02<- ggplot( toPlot )+geom_tile( aes( x=1, y=Var1, fill=ontology))+
            scale_fill_manual( values = c( "#D55E00","#009E73", "#0072B2"))+
            theme_minimal()+
            theme( axis.text = element_blank(), axis.title = element_blank(),
                   axis.ticks = element_blank(),  legend.position='bottom',
                   text=element_text( size=16))
          # plot clustering
          gg03<- ggdendro::ggdendrogram(oorder, rotate = T,)+
            ggdendro::theme_dendro() 
          
        }
        
        
        ### create a data-frame for the barplot
        datTOplot <- Reduce( rbind , lapply( iid , function(ii)
          {
          print(ii)
          datt <- datGO[[ii]]
          # select results for a given GO term, even if it's not a primary term in a given comparison
          datt <- datt$results[ match( GOtoPlot , datt$results$GO.ID )  , ]
          datt$dataset <- names(datGO)[ii]
          
          print( dim(datt) )
          
          ### add LFC or use log2Enrichment of enrichment
          if( isFALSE( datLFC ) ) {
            datt$LFC <- datt[match( GOtoPlot , rownames(datt)) , 'log2Enrichment']
          } else datt$LFC <- datLFC[ match( GOtoPlot , rownames(datLFC)), ii]
          
          # scale LFC data if asked
          if( isTRUE(scaleLFC))  datt$LFC  <- scale( datt$LFC , center = F)
          
          # make sore no terms are missing 
          datt$Ontology <- Ontology(GOTERM)[GOtoPlot]
          datt$Term <- Term(GOTERM)[GOtoPlot]
          datt$GO.ID <- GOtoPlot
          datt$Fisher[ is.na(datt$Fisher)] <-  1
          # if( isTRUE(typeSig) ) datt$Ontology <- Ontology(GOTERM)[GOtoPlot]
          return(datt)
        }))
        
        
        # reorder levels
        if( exists("datOrder")) datTOplot$dataset <- factor( datTOplot$dataset,
                                     levels = datOrder)
        
       
        # truncate labels
        datTOplot$Term <- sapply( datTOplot$Term , str_trunc, width = labelTRUNK)
        print(dim(datTOplot))
        
        # reorder Term using order of GO IDs from the clustering
        datTOplot$Term <- factor( datTOplot$Term, 
                                 levels = sapply( 
                                   oorder$labels[oorder$order] , 
                                   str_trunc, labelTRUNK ) )
        
       
        # log transform p-values
        datTOplot$log10.Fisher <- -log10(datTOplot$Fisher)
        
        # don't plot lfc for nonsig terms
         datTOplot$LFC <- ifelse( datTOplot$Fisher <0.05, datTOplot$LFC ,NA )
        
        # limit x axis
        datTOplot$log10.Fisher[ datTOplot$log10.Fisher>20] <- 20   

        
        # main barplot
        gg<- ggplot( datTOplot, aes(x=log10.Fisher, 
                                    y=Term ,
                                    fill=LFC ) ) + 
          { if(  !isFALSE(datLFC) ) scale_fill_binned_divergingx(na.value="grey",n.breaks=5 ) } +  
          # change color scale if LFC table is not provided to viridis
          {if(  isFALSE(datLFC) ) scale_fill_binned(type="viridis", na.value="grey",n.breaks=5 )} +
          ylab("GO terms") +
          geom_bar(stat = "identity",colour="black") + 
          facet_grid(cols = vars(dataset), 
                     # rows = vars(Ontology), 
                     scales = "free", space = "free_y")+
          theme_bw() + theme( text = element_text(size = 20 ), legend.position = "left",
                              axis.text.x = element_text(size = 16))
        
      # combine barplot and dendrogram
        ggl<- cowplot::plot_grid( plotlist = list(gg, gg02,gg03),align = "h", 
                                  nrow = 1, rel_widths = c( 10,0.5,1))
        
        return(ggl)
      }
     
# barplot for fsgsea results     
  fsgsea_barplot_clustered <- function( iid=iids,
                                        pathToPlot= topN_fgsea,
                                        dat.fgsea = fgsea_res ,
                                        datOrder,
                                        labelTRUNK=40 )
        {
  ## * iids - a numeric vector, defining which elements of datGO list to plot as columns of the barplot
  ## * GOtoPlot - a charchter vector of GO IDs for which datLFC will be plotted 
  ## * datGO - a list, where each element contains results of Robert's sf.createGoMatrix() funcion
  ## * datLFC - a matrix of mean LFCs (or other measures of GO changes) , if FALSE then log2Enrichment of GO test is used for color
  ## that will be used as a color of bars, if not provided log2FC of enrichment will be used
  ## * oorder - a charachter vector, defining order in which datasets (in columns) appear on the plot
  ## * labelTRUNK - logical value, if labels should be shorten
  
  require(colorspace)
  # require(go2gName)
  library(GeneOverlap)
  
  ### cluster terms based on gene set simmilarity
  {
    GOlist <- pathDB[ names(pathDB) %in% pathToPlot ]
    MM<- GeneOverlap::newGOM( GOlist , GOlist , genome.size=20000) ### set genome size to 10K when used with sc/sn
    MMjcc <- GeneOverlap::getMatrix(MM, name="Jaccard")
    GOid <- colnames( MMjcc )
    oorder <- hclust( as.dist(1-MMjcc) , method = "ward.D2")
    
    # prepare for plotting
    toPlot <- MMjcc
    toPlot <- reshape2::melt(toPlot)
    toPlot$yaxis_full <- toPlot$Var1
    
    # concatenate labels and order rows/columns by gene set simmilarity
    toPlot$Var1 <- factor(   sapply( as.character(toPlot$Var1)  , str_trunc, labelTRUNK) , 
                             levels =  sapply( oorder$labels[oorder$order] , str_trunc, labelTRUNK) )
    toPlot$Var2 <- factor(toPlot$Var2, levels = oorder$labels[oorder$order] )
    
   
    gg03<- ggdendro::ggdendrogram(oorder, rotate = T,)+
      ggdendro::theme_dendro() 
    
  }
  
  
  ### create a data-frame for the barplot
  datTOplot <- Reduce( rbind, lapply( iids, function(ii){
    print(ii)
    datt <-  dat.fgsea[[ii]]
    datt <-  datt[  datt$pathway %in% pathToPlot , ]
    datt$test <- names(dat.fgsea)[[ii]]
    datt <- as.data.frame(datt)
    datt <- datt[ ,colnames(datt)!="leadingEdge"]
    return(datt)
  }))
  
  
  # reorder levels
  if( exists("datOrder")) datTOplot$test <- factor( datTOplot$test ,
                                                       levels = datOrder)
  # rename one path
  datTOplot$pathway[datTOplot$pathway=="Actin.Ctsklt.fig1f"] <- "podocyte-enriched FA complex_PMID:28536193"
  
  # truncate labels
  if( !isFALSE(labelTRUNK)) {
    datTOplot$pathway <- sapply( sub( "__.*", "", datTOplot$pathway) , str_trunc, width = labelTRUNK)
    levels.order <- sapply(  sub( "__.*", "",   oorder$labels[oorder$order]) ,  str_trunc, labelTRUNK)
    } else {
      datTOplot$pathway <- sub( "__.*", "", datTOplot$pathway)
      levels.order <- sub( "__.*", "",  oorder$labels[oorder$order] ) 
    }
  
  print(dim(datTOplot))
  
  
  # reorder Term using order of GO IDs from the clustering
  datTOplot$pathway <- factor( datTOplot$pathway, 
                            levels = levels.order )
  
  # set NES to NA if not significant
  datTOplot$NES <- ifelse(datTOplot$pval<0.05, datTOplot$NES,NA )
  
  # main barplot
  gg<-  ggplot( datTOplot , aes(x = -log10(pval),
                                y = pathway, 
                                fill = NES )) + 
    # xlab("NES of gsea") + 
    #ylab("pathways") +
    # scale_size(range = c(0, 15))+
    scale_fill_binned_divergingx(na.value="grey",n.breaks=5 ) + 
    geom_bar(stat = "identity", color="black") + 
    facet_grid(cols = vars(test),  scales = "free", space = "free_y")+
    theme_bw() + theme( text = element_text(size = 22 ),legend.position = "left",
                        axis.text.x = element_text(size = 14)) 
  
  # combine barplot and dendrogram
  ggl<- cowplot::plot_grid( plotlist = list(gg, gg03),
                            # align = "h", 
                            nrow = 1, rel_widths = c( 10,1))
  
  return(ggl)
}


####======== 2D plots ==========

#### 2D plot for Robert's GO results:
## compares mean LFC (ctrl vs exprmnt) of GO terms in 2 conditions, 
## a term should be significant for at least one of the 2 conditions
  GO_2Dplot <- function( GOrb_list  , 
                         meanLFCdat , 
                         ids , 
                         plotRanks =TRUE,
                         contrasts , 
                         cnfdlvl=0.99,
                         thrsh = 0.05,
                         trunc=50 ) 
    {
     
     ## * GOrb_list - list of results for GO annotation, generated by sf.clusterGoByGeneset()
     ## * meanLFCdat - a numeric matrix or dataframe, containing mean LFC of GO gene members, 
     ## column names should equal to GOrb_list names
     ## * ids - 2 numeric values, ids of 2 datasets to be compared, will be used
     ## to select ids elements from GOrb_list and ids columns from meanLFCdat
     ## * dataName - character vector, descriptive names of 2 DEtests
     ## * contrasts - character vector, labels that differntiate 2 DEtests
     # x axis - first dataset, y-axis - second
     ## * cnfdlvl - a numeric value between 0 and 1 for the confidence interval
     # of a regression that fits mean LFCs of GO terms of 2 FSGS comparisons:
     # only terms outside of the conf.int will be labeled
    ### trunc - a numerical value, length to truncate GO terms
     
     require( ggrepel )
     
     # get GO terms significant in at least one stage
     X <- union(GOrb_list[[ids[1]]]$results$GO.ID[which(GOrb_list[[ids[1]]]$results$Fisher< thrsh)],
                GOrb_list[[ids[2]]]$results$GO.ID[which(GOrb_list[[ids[2]]]$results$Fisher< thrsh )] )
  
     # get mean LFC for the terms of interest
     GOrobert_LFC <- as.data.frame( meanLFCdat [ rownames( meanLFCdat ) %in% X , ids] )
     GOrobert_LFC[is.na(GOrobert_LFC)]<- 0 
     GOrobert_LFC <- GOrobert_LFC[rowSums(GOrobert_LFC!=0)>0,]

     # # shorten the names
     GOrobert_LFC$Primary <- goterms[ match( rownames(GOrobert_LFC), names(goterms))]
     colnames(GOrobert_LFC)[1:2 ]<- c("early","late")
     # ## add Ranks
     # GOrobert_LFC$early_rank <- rank( GOrobert_LFC[,1])
     # GOrobert_LFC$late_rank <- rank( GOrobert_LFC[,2])
     rrho <- cor( GOrobert_LFC$early, GOrobert_LFC$late, method = "spearman")
     ### 
     if( abs( rrho ) >0.2 ) {
       # Create prediction interval data frame with upper and lower lines corresponding to sequence covering minimum and maximum of x values in original dataset
       newx <- lm(  formula = GOrobert_LFC$late ~ GOrobert_LFC$early, )
       pred_interval0 <- predict(newx, interval="prediction", level = cnfdlvl)
       pred_interval0 <- as.data.frame(pred_interval0)
       pred_interval <- cbind(pred_interval0 , GOrobert_LFC )
       GOrobert_LFC <- cbind(GOrobert_LFC , pred_interval0)

       ## add size as -log10 pvalue
       logP <- -log10( cbind( 
         GOrb_list[[ids[1]]]$results$Fisher[ 
            match( rownames(GOrobert_LFC), GOrb_list[[ids[1]]]$results$GO.ID) ], 
         GOrb_list[[ids[2]]]$results$Fisher[
          match( rownames(GOrobert_LFC) , GOrb_list[[ids[2]]]$results$GO.ID) ] 
       ) )
       logP[ is.na(logP)]<- 0
       GOrobert_LFC$size <-  rowMax(logP )
       GOrobert_LFC$size <- ifelse( GOrobert_LFC$size < 2, 0, GOrobert_LFC$size )
       
       # labels
       GOrobert_LFC$GOlabel <- ifelse( (GOrobert_LFC$late < GOrobert_LFC$lwr  |
                                          GOrobert_LFC$late > GOrobert_LFC$upr) & GOrobert_LFC$size>0 , 
                                       as.character(GOrobert_LFC$Primary), "")
       # add type of GO
       GOrobert_LFC$GOtype <-  ifelse( 
         (GOrobert_LFC$late < GOrobert_LFC$lwr  |
            GOrobert_LFC$late > GOrobert_LFC$upr) & GOrobert_LFC$size>0 ,
         as.character(  Ontology(GOTERM)[rownames(GOrobert_LFC)]), " ")
       
       # # shorten the names
        GOrobert_LFC$GOlabel <-  sapply(GOrobert_LFC$GOlabel , str_trunc, trunc)
       
       # plot
       gg <-  ggplot( GOrobert_LFC , aes(x= early ,y= late) ) +  
         geom_point(aes( size = size ,  color= GOtype ,  fill= GOtype ), 
                    shape=21, stroke = 2, alpha=0.75) + 
         scale_color_manual( values = c("BP" ="#D55E00", "CC" ="#009E73",
                                        "MF" ="#0072B2", " " = "grey" ) )+
         scale_fill_manual( values = c("BP" ="#D55E00", "CC" ="#009E73", 
                                       "MF" ="#0072B2", " " = "grey" ) )+
         geom_ribbon( data=pred_interval, aes(ymin = lwr, ymax = upr), fill = "blue", alpha = 0.1) + 
         geom_hline(yintercept=0, linetype="dashed", color = "black")+
         geom_vline(xintercept=0, linetype="dashed", color = "black")+
         scale_size(range = c(1, 30)) +  # adjust range of bubbles sizes
         geom_text_repel( aes(label = GOlabel ,colour=GOtype), 
                          max.overlaps=150, cex=3 ,
                          max.time	= 200 ) + #ensure that labels are not jammed together
         xlab(paste("mean log2FC of GO at", contrasts[1],"weeks", sep = " ")) + 
         ylab(paste("mean log2FC of GO at", contrasts[2],"weeks", sep = " ")) + 
         ggtitle(paste( "activity changes in GO terms\n",
                        rrho , sep = "")) + theme_bw()+
         theme( text = element_text(size = 24))
       
     } else {
       print("no correlation")
       
       GO_meanLFC.sn_test <- apply( meanLFCdat[,ids], 2, function(values)
       {
         # Calculate the empirical cumulative distribution function
         ecdf_function <- ecdf(values)
         
         # Calculate p-values for each value in the vector
         p_values <- sapply(values, function(x) {
           # Two-tailed test: P-value is 2 times the smallest tail probability
           min(ecdf_function(x), 1 - ecdf_function(x)) * 2
         })
         
         # Print the calculated p-values
         return(p_values)
       })
       
       
       # labels
       GOrobert_LFC$GOlabel <- ifelse( 
         rownames( GOrobert_LFC ) %in% rownames(GO_meanLFC.sn_test)[
           rowSums(GO_meanLFC.sn_test<0.05)>0 ] ,
         as.character(GOrobert_LFC$Primary), "")
       
       # add size
       GOrobert_LFC$size <- sapply( rownames(GOrobert_LFC), 
                                    function(X) length( unique( go2gName[[X]] )))
       
     
       
       
       # add type of GO
       GOrobert_LFC$GOtype <-  ifelse(   rownames( GOrobert_LFC ) %in% rownames(GO_meanLFC.sn_test)[
         rowSums(GO_meanLFC.sn_test<0.05)>0 ]  ,
         as.character(  Ontology(GOTERM)[rownames(GOrobert_LFC)]), " ")
       
       # plot
       gg <-  ggplot( GOrobert_LFC , aes(x= early ,y= late) ) +  
         geom_point(aes( size = size ,  color= GOtype ), shape=21, stroke = 2) + 
         scale_color_manual( values = c("BP" ="#D55E00", "CC" ="#009E73", 
                                        "MF" ="#0072B2", " " = "grey" ) )+
         geom_hline(yintercept=0, linetype="dashed", color = "black")+
         geom_vline(xintercept=0, linetype="dashed", color = "black")+
         scale_size(range = c(1, 30)) +  # adjust range of bubbles sizes
         geom_text_repel( aes(label = GOlabel ,colour=GOtype), 
                          max.overlaps=150, cex=3 ,
                          max.time	=200) + #ensure that labels are not jammed together
         xlab(paste("mean log2FC of GO at", contrasts[1],"weeks", sep = " ")) + 
         ylab(paste("mean log2FC of GO at", contrasts[2],"weeks", sep = " ")) + 
         ggtitle(paste( "activity changes in GO terms\n",
                        rrho, sep = "")) + theme_bw()+
         theme( text = element_text(size = 24))
     }
 

    return(gg)
   }   

#### 2Dway  GSEA plot 
      
      GSEA_2Dplot <- function( gsea_list = fgsea_res  , 
                             ids , 
                             dataName , 
                             contrasts , 
                             cnfdlvl=0.99,
                             thrsh = 0.05,
                             trunc=50 ) 
      {
        
        ## * gsea_list - list of results for GSEA results from fgsea::fgseaMultilevel()
        ## column names should equal to GOrb_list names
        ## * ids - 2 numeric values, ids of 2 datasets to be compared, will be used
        ## to select ids elements from GOrb_list and ids columns from meanLFCdat
        ## * dataName - character vector, descriptive names of 2 DEtests
        ## * contrasts - character vector, labels that differntiate 2 DEtests
        # x axis - first dataset, y-axis - second
        ## * cnfdlvl - a numeric value between 0 and 1 for the confidence interval
        # of a regression that fits mean LFCs of GO terms of 2 FSGS comparisons:
        # only terms outside of the conf.int will be labeled
        ### trunc - a numerical value, length to truncate GO terms
        
        require( ggrepel )
        
        # get GO terms significant in at least one stage
        X <- union(fgsea_res[[ids[1]]]$pathway[ which(fgsea_res[[ids[1]]]$pval < thrsh)],
                   fgsea_res[[ids[2]]]$pathway[ which(fgsea_res[[ids[2]]]$pval < thrsh )] )
        
        # get mean LFC for the terms of interest
        fgsea_NES <- data.frame( 
          early= fgsea_res[[ids[1]]]$NES[  match(X ,fgsea_res[[ids[1]]]$pathway ) ],
          late= fgsea_res[[ids[2]]]$NES[  match(X ,fgsea_res[[ids[2]]]$pathway ) ])
        fgsea_NES[is.na(fgsea_NES)]<- 0 
        fgsea_NES <- fgsea_NES[rowSums(fgsea_NES!=0)>0,]
        fgsea_NES$pathway <- X
        
  
        
        ### 
        if( abs(cor( fgsea_NES$early, fgsea_NES$late)) >0.2 ) {
          # Create prediction interval data frame with upper and lower lines corresponding to sequence covering minimum and maximum of x values in original dataset
          newx <- lm(  formula = fgsea_NES$late ~ fgsea_NES$early, )
          pred_interval0 <- predict(newx, interval="prediction", level = cnfdlvl)
          pred_interval0 <- as.data.frame(pred_interval0)
          pred_interval <- cbind(pred_interval0 , fgsea_NES )
          fgsea_NES <- cbind(fgsea_NES , pred_interval0)
          
      
          ## add size
         logP <- -log10( cbind( 
           fgsea_res[[ids[1]]]$pval[ 
              match( X , fgsea_res[[ids[1]]]$pathway ) ], 
           fgsea_res[[ids[2]]]$pval[
              match( X , fgsea_res[[ids[2]]]$pathway ) ] 
          ) )
         
          logP[ is.na(logP)]<- 0
          fgsea_NES$size <-  rowMax(logP )
          fgsea_NES$size <- ifelse( fgsea_NES$size < 2, 0, fgsea_NES$size )
          
          # add labels
          fgsea_NES$Plabel <- ifelse( ( fgsea_NES$late < fgsea_NES$lwr  |
                                          fgsea_NES$late > fgsea_NES$upr)  & fgsea_NES$size >0  , 
                                      as.character(fgsea_NES$pathway), "")
          # add type of GO
          fgsea_NES$Ptype <-  ifelse( 
            ( fgsea_NES$late < fgsea_NES$lwr  |
              fgsea_NES$late > fgsea_NES$upr) & fgsea_NES$size >0  ,
            as.character(  sub(".*__|HALLMARK.*","|HALLMARK",fgsea_NES$pathway)), " ")
          
          # 
          fgsea_NES$Ptype <- ifelse( fgsea_NES$Ptype =="|HALLMARK","HALLMARK" ,
                                     ifelse( fgsea_NES$Ptype %in% c( "|HALLMARKKEGG",
                                                                     "|HALLMARKREACT" ) , 
                                             sub( "\\|HALLMARK", "" , fgsea_NES$Ptype) ,""))
          # # shorten the names
          fgsea_NES$Plabel <-  sapply( fgsea_NES$Plabel , str_trunc, trunc)
          
          # plot
          gg <-  ggplot( fgsea_NES , aes(x= early ,y= late) ) +  
            geom_point(aes( size = size ,  color= Ptype ,  fill= Ptype ), 
                       shape=21, stroke = 2, alpha=0.75) + 
            scale_color_manual( values = c("HALLMARK" ="#D55E00", "KEGG" ="#009E73",
                                           "REACT" ="#0072B2", " " = "grey" ) )+
            scale_fill_manual( values = c("HALLMARK" ="#D55E00", "KEGG" ="#009E73", 
                                          "REACT" ="#0072B2", " " = "grey" ) )+
            geom_ribbon( data=pred_interval, aes(ymin = lwr, ymax = upr), fill = "blue", alpha = 0.1) + 
            geom_hline(yintercept=0, linetype="dashed", color = "black")+
            geom_vline(xintercept=0, linetype="dashed", color = "black")+
            scale_size(range = c(1, 30)) +  # adjust range of bubbles sizes
            geom_text_repel( aes(label = Plabel ,colour=Ptype), 
                             max.overlaps=150, cex=3 ,
                             max.time	= 200 ) + #ensure that labels are not jammed together
            xlab(paste("NES of gsea at", contrasts[1],"weeks", sep = " ")) + 
            ylab(paste("NES of gsea at", contrasts[2],"weeks", sep = " ")) + 
            ggtitle(paste( "activity changes in pathways\n",
                           dataName, sep = "")) + theme_bw()+
            theme( text = element_text(size = 24))
          
        } else {
          print("no correlation")
          
          # GO_meanLFC.sn_test <- apply( meanLFCdat[,ids], 2, function(values)
          # {
          #   # Calculate the empirical cumulative distribution function
          #   ecdf_function <- ecdf(values)
          #   
          #   # Calculate p-values for each value in the vector
          #   p_values <- sapply(values, function(x) {
          #     # Two-tailed test: P-value is 2 times the smallest tail probability
          #     min(ecdf_function(x), 1 - ecdf_function(x)) * 2
          #   })
          #   
          #   # Print the calculated p-values
          #   return(p_values)
          # })
          # 
          # 
          # # labels
          # GOrobert_LFC$GOlabel <- ifelse( 
          #   rownames( GOrobert_LFC ) %in% rownames(GO_meanLFC.sn_test)[
          #     rowSums(GO_meanLFC.sn_test<0.05)>0 ] ,
          #   as.character(GOrobert_LFC$Primary), "")
          # 
          # # add size
          # GOrobert_LFC$size <- sapply( rownames(GOrobert_LFC), 
          #                              function(X) length( unique( go2gName[[X]] )))
          # 
          # 
          # 
          # 
          # # add type of GO
          # GOrobert_LFC$GOtype <-  ifelse(   rownames( GOrobert_LFC ) %in% rownames(GO_meanLFC.sn_test)[
          #   rowSums(GO_meanLFC.sn_test<0.05)>0 ]  ,
          #   as.character(  Ontology(GOTERM)[rownames(GOrobert_LFC)]), " ")
          # 
          # # plot
          # gg <-  ggplot( GOrobert_LFC , aes(x= early ,y= late) ) +  
          #   geom_point(aes( size = size ,  color= GOtype ), shape=21, stroke = 2) + 
          #   scale_color_manual( values = c("BP" ="#D55E00", "CC" ="#009E73", 
          #                                  "MF" ="#0072B2", " " = "grey" ) )+
          #   geom_hline(yintercept=0, linetype="dashed", color = "black")+
          #   geom_vline(xintercept=0, linetype="dashed", color = "black")+
          #   scale_size(range = c(1, 30)) +  # adjust range of bubbles sizes
          #   geom_text_repel( aes(label = GOlabel ,colour=GOtype), 
          #                    max.overlaps=150, cex=3 ,
          #                    max.time	=200) + #ensure that labels are not jammed together
          #   xlab(paste("mean log2FC of GO at", contrasts[1],"weeks", sep = " ")) + 
          #   ylab(paste("mean log2FC of GO at", contrasts[2],"weeks", sep = " ")) + 
          #   ggtitle(paste( "activity changes in GO terms\n",
          #                  dataName, sep = "")) + theme_bw()+
          #   theme( text = element_text(size = 24))
        }
        
        
        return(gg)
      }   
      



 