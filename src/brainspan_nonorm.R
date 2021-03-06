library(NetBID2)
library(tidyverse)
library(stringr)
project_main_dir <- '/cluster/home/chenhy/project/Brainspan/network' # user defined main directory for the project, one main directory could have multiple project folders, distinguished by project name.
project_name <- "brainspan_nonorm" # project name for the project folders under main directory.
# Create a hierarchcial working directory and return a list contains the hierarchcial working directory information
# This list object (network.par) is an ESSENTIAL variable in network construction pipeline
network.par  <- NetBID.network.dir.create(project_main_dir=project_main_dir,project_name=project_name)

load("/cluster/home/chenhy/project/Brainspan/db/prenatal_eset.RData")
meta <- pData(pre_eset)
network.par$net.eset <- pre_eset
# QC for the raw eset
draw.eset.QC(network.par$net.eset,outdir=network.par$out.dir.QC,
             intgroup=c("class","gender","class1"),
             do.logtransform=FALSE,prefix='beforeQC_',
             choose_plot = c("heatmap","pca"),
             pre_define=c('prenatal'='blue','adult'='red'))
# Save Step 1 network.par as RData
NetBID.saveRData(network.par = network.par,step='exp-load')

############### Step 2: Normalization for the expression dataset (exp-QC) ###############
NetBID.loadRData(network.par = network.par,step='exp-load')
# Reload network.par RData from Step 1
mat <- exprs(network.par$net.eset)

## Firstly, remove any gene that did not have at least one expression value greater than or equal to five RPKM in any of all tissue samples.
mat <- mat[!(rownames(mat) %in% names(which((apply(exprs(pre_eset),1,max)<5)==1))),]
#查看RPKM为0的行和列
sample_na_count <- apply(mat,1,function(x){length(which(x==0))})
print(table(sample_na_count))
gene_na_count <- apply(mat,2,function(x){length(which(x==0))})
print(table(gene_na_count))
# 把表达值为0的都认定为缺失值，并查看每行缺失值的比例
#mat[which(mat==0)] <- NA
#library(DMwR)
#length(manyNAs(mat,0.5))#每行RPKM为0的比例≥50%的有143行，所以将所有单元格+1,方便取对数
mat <- mat+1
## Secondly, the log2 transformation.
med_val <- median(apply(mat,2,median)); print(med_val)
if(med_val>5){mat <- log2(mat)}
## Thirdly, the quantile normalization across samples.
# Perform limma quantile normalization
#mat <- normalizeQuantiles(mat)
## Fourthly, filter out genes with very low expression values (bottom 5%) in most samples (more than 90%).
# Filter out low-expression genes
choose1 <- apply(mat<= quantile(mat, probs = 0.05), 1, sum)<= ncol(mat) * 0.90
print(table(choose1))
mat <- mat[choose1,]
violin_plot(mat[,1:10])
#The remaining set consisted of 13,563 expressed genes. DOI: 10.1117/12.2044384

# Update eset with normalized expression matrix
net_eset <- generate.eset(exp_mat=mat, phenotype_info=pData(network.par$net.eset)[colnames(mat),],
                          feature_info=fData(network.par$net.eset)[rownames(mat),],
                          annotation_info=annotation(network.par$net.eset))
# Updata network.par with new eset
network.par$net.eset <- net_eset

# QC for the normalized eset
draw.eset.QC(network.par$net.eset,outdir=network.par$out.dir.QC,
             intgroup=c("structure_acronym","class1"),
             do.logtransform=FALSE,prefix='afterQC_',
             choose_plot=c('heatmap','pca','density'),
             pre_define=c('prenatal'='blue','adult'='red'))
# Save Step 2 network.par as RData
NetBID.saveRData(network.par = network.par,step='exp-QC')

############### Step 3: Check sample cluster analysis, optional (exp-cluster) ###############

# Reload network.par RData from Step 2
NetBID.loadRData(network.par = network.par,step='exp-QC')

# Select the most variable genes across samples
mat <- exprs(network.par$net.eset)
choose1 <- IQR.filter(exp_mat=mat,use_genes=rownames(mat),thre = 0.5)
print(table(choose1))
mat <- mat[choose1,]

# Generate temporary eset
tmp_net_eset <- generate.eset(exp_mat=mat, phenotype_info=pData(network.par$net.eset)[colnames(mat),],
                              feature_info=fData(network.par$net.eset)[rownames(mat),], annotation_info=annotation(network.par$net.eset))
# QC plot for IQR filtered eset
draw.eset.QC(tmp_net_eset,outdir=network.par$out.dir.QC,intgroup=c("structure_acronym","class1"),choose_plot=c('heatmap','pca','density'),
             do.logtransform=FALSE,prefix='Cluster_',
             pre_define=c('prenatal'='blue','adult'='red'),pca_plot_type='2D.interactive')
# The following scripts provide various ways to visualize and check if the IQR filter selected genes
# can be used to perform good sample cluster analysis (predicted labels vs. real labels). Figures will be displayed instead of saving as files.

# Extract phenotype information data frame from eset
phe <- pData(network.par$net.eset)
net_eset <- network.par$net.eset
# Extract all "cluster-meaningful" phenotype columns
intgroup <- c("age","gender","class1","structure_name","donor_id")
# Cluster analysis using Kmean and plot result using PCA biplot (pca+kmeans in 2D)
for (i in intgroup) {
  pdf(sprintf('pca_%s.pdf',i),width=10,height=5)
  draw.emb.kmeans(mat=mat[choose1,],all_k = NULL,
                  obs_label=get_obs_label(phe,i),
                  plot_type='2D.text')
  dev.off()
}
# Reclassify the variable class1 and window.
w1 <- grep('pcw',phe$age);phe$week[w1] <- as.numeric(gsub("(.*) pcw","\\1",phe$age[w1]))
w1 <- grep('mos',phe$age);phe$week[w1] <- 42+4*as.numeric(gsub("(.*) mos","\\1",phe$age[w1]))
w1 <- grep('yrs',phe$age);phe$week[w1] <- 42+52*as.numeric(gsub("(.*) yrs","\\1",phe$age[w1]))
phe$week_numeric <- as.numeric(phe$week)
phe$cortex <- ifelse(grepl("cortex",phe$structure_name),'cortex',phe$structure_name)
phe$class1 <- ifelse(phe$week_numeric<=9,'Embryo',
                     ifelse(phe$week_numeric<=14,'Prenatal_1st-Trimester',
                            ifelse(phe$week_numeric<=28,'Prenatal_2nd-Trimester',
                                   ifelse(phe$week_numeric<=42,'Prenatal_3rd-Trimester',
                                          ifelse(phe$week_numeric<=42+52*13,'Childhood','Adulthood')))))

phe <- within(phe,{
  window <- NA
  window[week_numeric<=34] <- "w1-w4"
  window[week_numeric>34 & week_numeric<=63] <- "w5"
  window[week_numeric>63] <- "w6-w9"
})
pData(net_eset) <- phe

# Update network.par with new eset
network.par$net.eset <- net_eset
NetBID.saveRData(network.par = network.par,step='exp-QC')
############### Step 4: Prepare files to run SJARACNe (sjaracne-prep) ###############

# Reload network.par RData from Step 2
NetBID.loadRData(network.par = network.par, step='exp-QC') ## do not load file from exp-cluster

# Load database
db.preload(use_level='transcript',use_spe='human',update=FALSE)

# Converts gene ID into the corresponding TF/SIG list
use_gene_type <- 'external_gene_name' # user-defined
use_genes <- rownames(fData(network.par$net.eset))
use_list  <- get.TF_SIG.list(use_genes,use_gene_type=use_gene_type)

# Select samples for analysis
use.samples <- rownames(phe) 
SJAracne.prepare(eset=network.par$net.eset,use.samples=use.samples,
                 TF_list=use_list$tf,SIG_list=use_list$sig,
                 IQR.thre = 0.5,IQR.loose_thre = 0.1,
                 SJAR.project_name="all_brain",SJAR.main_dir=network.par$out.dir.SJAR)
#===========================================analysis=================================================
######### Step 1: Load in gene expression dataset for analysis (exp-load, exp-cluster, exp-QC) ###############
# Get the demo's constructed network data
network.dir <- sprintf("/cluster/home/chenhy/project/Brainspan/network/%s",project_name) # use demo network in the package
network.project.name <- 'all_brain'
analysis.par  <- NetBID.analysis.dir.create(project_main_dir=project_main_dir, project_name=project_name,
                                            network_dir=network.dir, network_project_name=network.project.name)
analysis.par$cal.eset <- network.par$net.eset

# Save Step 1 network.par as RData
NetBID.saveRData(analysis.par=analysis.par,step='exp-QC')

############### Step 2: Read in network files and calcualte driver activity (act-get) ###############

# Reload network.par RData from Step 1
NetBID.loadRData(analysis.par=analysis.par,step='exp-QC')
# Get network information
analysis.par$tf.network  <- get.SJAracne.network(network_file=analysis.par$tf.network.file)
analysis.par$sig.network <- get.SJAracne.network(network_file=analysis.par$sig.network.file)

# Creat QC report for the network
draw.network.QC(analysis.par$tf.network$igraph_obj,outdir=analysis.par$out.dir.QC,prefix='TF_net_',html_info_limit=FALSE)
draw.network.QC(analysis.par$sig.network$igraph_obj,outdir=analysis.par$out.dir.QC,prefix='SIG_net_',html_info_limit=TRUE)

# Merge network first
analysis.par$merge.network <- merge_TF_SIG.network(TF_network=analysis.par$tf.network,SIG_network=analysis.par$sig.network)

# Get activity matrix
ac_mat <- cal.Activity(target_list=analysis.par$merge.network$target_list,cal_mat=exprs(analysis.par$cal.eset),es.method='weightedmean')
# Create eset using activity matrix
analysis.par$merge.ac.eset <- generate.eset(exp_mat=ac_mat,phenotype_info=pData(analysis.par$cal.eset)[colnames(ac_mat),],
                                            feature_info=NULL,annotation_info='activity in net-dataset')
# Save Step 2 analysis.par as RData
NetBID.saveRData(analysis.par=analysis.par,step='act-get')

