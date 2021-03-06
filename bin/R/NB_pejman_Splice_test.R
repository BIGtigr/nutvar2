setwd("~/Dropbox/Proyecto_NutVar2/nutvar2/data/training")

#install.packages("functional")

data<-read.table("Table.txt")
data_imputed<-read.table("Table_imputed.txt")

# Subset the input data between the different groups

stop_gain<-subset(data, data$group == "Non_Pathogenic_stop" | data$group == "Pathogenic_stop")
frameshift<-subset(data, data$group == "Non_Pathogenic_frameshift" | data$group == "Pathogenic_frameshift")
splice<-subset(data, data$group == "Non_Pathogenic_splice" | data$group == "Pathogenic_splice")

stop_gain_imputed<-subset(data_imputed, data_imputed$group == "Non_Pathogenic_stop" | data_imputed$group == "Pathogenic_stop")
frameshift_imputed<-subset(data_imputed, data_imputed$group == "Non_Pathogenic_frameshift" | data_imputed$group == "Pathogenic_frameshift")
splice_imputed<-subset(data_imputed, data_imputed$group == "Non_Pathogenic_splice" | data_imputed$group == "Pathogenic_splice")

# Discard features I am not going to use; the eexistence of protein domain or site info
# (DOMAIN INFO, column 8, and SITE INFO, column 13, and the columns 18-21 indicating
# belonging to the Innate Immune Response)

splice_imputed<-splice_imputed[,c(1,3:7,9:12,14:17,22:24)]
splice<-splice[,c(1,3:7,9:12,14:17,22:24)]

# Open the libraries I am going to need

library(ROCR)

# Declare variables and lists to be used in the loop
d2 = splice_imputed

# This is the number of folds

knumber<-10

# This is the length of the vector of indexes

N<-length(d2$group)

# These are the lists in which results will be stored

result.P<-vector("list", knumber)
result.combined<-vector("list", knumber)
result.combined.RVIS<-vector("list", knumber)
result.sole<-vector("list", knumber)
result.sole.RVIS<-vector("list", knumber)
True.class<-vector("list", knumber)


# Create the fold vector

index.select<-sample(rep(1:knumber, length=N), N, replace = FALSE)

# Add it to the matrix of data

d2$fold<-index.select

##############################################################################################################
############################# NaiveBayes code ################################################################
##############################################################################################################

# We first separate the training and test subsets from the initial data. The total number
# of folds is knumber.

for(i in 1:knumber)
{

# We exclude the last column which is the d2.fold
  
d2.train<-d2[d2$fold != i,c(1:(ncol(d2)-1))]
d2.test<-d2[d2$fold == i,c(1:(ncol(d2)-1))]

# We calculate the variance for each feature for the whole set of observations.
# We exclude the group colum and the MCArthur (pRDG) and RVIS scores

var.vector<-apply(d2.train[c(-15,-16,-17)],2,var,na.rm=TRUE)
min(var.vector)
for(t in 1:length(var.vector))
{
  if(var.vector[i] == 0)
  {
    var.vector[i]<-0.001
  }  
}
min(var.vector)


# Second the means per group. We have to apply lapply so we need to 
# divide the table in two sets of columns, columns that are NP and 
# columns that are P.

# First, subset NP and P without including group and without NMD_derived for Stop_gains

d2.train.NP<-subset(d2.train[-17], d2.train$group == "Non_Pathogenic_splice")
d2.train.P<-subset(d2.train[-17], d2.train$group == "Pathogenic_splice")

# Then convert to a matrix, transpose and back to a data frame

x<-as.data.frame(t(as.matrix(d2.train.NP)))
y<-as.data.frame(t(as.matrix(d2.train.P)))

# Then columnbind the resulting dataframes

d3.means<-cbind(x,y)

# Then use grp with the actual levels in use as the factor to indicate the
# group belonging of the columns (first 368 are NP, the rest are P)

grp<-factor(droplevels(d2.train$group))

# Finally do the lapply

means.list<-lapply(as.list(as.character(levels(grp))), FUN = function(x, cn, data) {
  rowMeans(data[grp %in% x],na.rm=TRUE)
}, cn = grp, data = d3.means)

#################################################################################
############################### THE NB CODE #####################################
#################################################################################

# Create the variables of likelihood

# Define a factor indicating qualitative (1) and quantitative (2) sequence based features

qualitative.quantitative.factor<-factor(c(2,1,1,1,2,2,2,2,2,1,2,2,2,1))

# We declare vectors to store results

results<-NULL
McArthur<-NULL
RVIS<-NULL
combined<-NULL
sole.MC<-NULL
combined.RVIS<-NULL
sole.RVIS<-NULL
d2.test.class<-droplevels(as.factor(d2.test$group))

# For all the rows in the test set 

for (h in 1:nrow(d2.test))
{
  
  # WE declare the initial probabilities of being pathogenic (.P) and non pathogenic (.NP)
  # There are also two lists to store partial probabilities
  
  Likelihood.NP<-1
  Likelihood.P<-1
 # print(Likelihood.NP)
  print(Likelihood.P)
  
  vector.partial.probs.P<-vector("list", ncol(d2.train[c(-15,-16,-17)]))
  vector.partial.probs.NP<-vector("list", ncol(d2.train[c(-15,-16,-17)]))
  
  for (j in 1:ncol(d2.test[c(-15,-16,-17)]))
  {
      # If the feature is qualitative
      
      if(as.numeric(qualitative.quantitative.factor[j]) == 1)
      {
        # Pathogenic probability
      
        # Recover the mean from the least of Pathogenic means means.list[2]
        
        features.P<-means.list[[2]]
        mu1<-as.numeric(features.P[j])
        # print(mu1)
        
        # Calculate the probability as modelized by Bernoulli
        
        Likelihood.P<-Likelihood.P*(mu1*d2.test[h,j] + ((1-mu1)*(1-d2.test[h,j])))
        
        vector.partial.probs.P[[j]]<-Likelihood.P
        
        # Healthy probability
        
        # Do the same for the probability of being Non.pathogenic
        
        features.NP<-means.list[[1]]
        mu2<-as.numeric(features.NP[1])
       # print(mu2)
        
        Likelihood.NP<-Likelihood.NP*(mu2*d2.test[h,j] + ((1-mu2)*(1-d2.test[h,j])))
        
        vector.partial.probs.NP[[j]]<-Likelihood.NP
        
      }
      
      # If the feature is quantitative
      
      if(as.numeric(qualitative.quantitative.factor[j]) == 2)
      {
        
        # Pathogenic probability. We model it as a Normal Distribution.
        
        features.P<-means.list[[2]]
       
        # print("Feature quantitative", features.P)
        mu1<-as.numeric(features.P[j])
        
        a.P<-sqrt(2*pi*var.vector[j])
        b.P<-var.vector[j]
        e.P<-(d2.test[h,j]-mu1)^2
        f.P<-e.P/(2*b.P)
        
        g.P<-exp(-f.P)
        
        Likelihood.P<-Likelihood.P*((1/a.P)*g.P)
        
        vector.partial.probs.P[[j]]<-Likelihood.P
        
        # Healthy probability
        
        features.NP<-means.list[[1]]
        mu2<-as.numeric(features.NP[j])
        
        a.NP<-sqrt(2*pi*var.vector[j])
        b.NP<-var.vector[j]
        e.NP<-(d2.test[h,j]-mu2)^2
        f.NP<-e.NP/(2*b.NP)
        
        g.NP<-exp(-f.NP)
        
        Likelihood.NP<-Likelihood.NP*((1/a.NP)*g.NP)
        
        vector.partial.probs.NP[[j]]<-Likelihood.NP
      }
   # print (vector.partial.probs.P)
  #  print ( vector.partial.probs.NP)
      
      # Now we calculate the posterior probability of being pathogenic with equal priors
      
      pIso <- (0.5*Likelihood.P)/((0.5*Likelihood.P) + (0.5*Likelihood.NP))
  print("j")
  print(j)
  print("Likelihood.P")
  print(Likelihood.P)
  print("Iso")
  print(pIso)
 
     #print(Likelihood.NP)
      
      # Then we extract the MCArhtur and RVIS scores from the test subset
      
      pMCArhtur<-d2.test[h,15]
      originalRVIS<-d2.test[h,16]
      
      # We transform the RVIS score to a probability
      
      o<-(1+exp(originalRVIS))
      pRVIS<-(1/o)
      #print (pIso)
      
      # We store the results of each fold in vectors 
      
      results[h]<-pIso
      McArthur[h]<-pMCArhtur
      RVIS[h]<-pRVIS
  }
  # print (results)
}
print(results)
# For combined scores we multiply probabilities whenever MCArthur or RVIS are not NAs

for (k in 1:length(results))
{
  v<-as.numeric(is.na(McArthur[[k]]))
  if(v !=1)
  {
    combined[k]<-(results[k]*McArthur[k])
    sole.MC[k]<-McArthur[k]
    
  }
  w<-as.numeric(is.na(RVIS[[k]]))
  if(w !=1)
  {
    combined.RVIS[k]<-(results[k]*RVIS[k])
    sole.RVIS[k]<-RVIS[k]
  }
}



# We store the result vectors and the true class in a list
#print (results)
result.P[[i]]<-results
True.class[[i]]<-d2.test.class
result.combined[[i]]<-combined
result.combined.RVIS[[i]]<-combined.RVIS
result.sole[[i]]<-sole.MC
result.sole.RVIS[[i]]<-sole.RVIS
}
#print(result.P)
