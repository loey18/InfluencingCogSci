library(stm)
library(stringr)
library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
require(cleanNLP)
require(udpipe)
require(stringi)
library(knitr)
library(GGally)
library(network)
library(sna)
library(wordcloud)

# Resources:
# http://www.structuraltopicmodel.com/

##################
### PROCESSING ###
##################

clean_abstracts <- function(data_frame) {
  # Clean abstract column
  # Removes punctuation and escape characters, "\\n", "\\t", "\\f".
  # Creates exception for words containing punctuation, "e.g." & "i.e."
  data_frame$abstract <- as.character(data_frame$abstract, na.omit = T)
  data_frame <- data_frame %>%
    mutate(abstract_cleaned = str_replace_all(abstract, c("e\\.g\\."="e1g1", "i\\.e\\."="i1e1")),
           abstract_cleaned = str_replace_all(abstract_cleaned, c("[^a-zA-Z0-9\\&\\s]"=" ", "[\\n\\t\\f]"="")),
           abstract_cleaned = str_replace_all(abstract_cleaned, c("e1g1"="e.g.", "i1e1"="i.e.")))
  return(data_frame)
}

structure_text <- function(documents, metadata = NA) {
  print("Processing documents")
  if (!is.na(metadata)) {
    processed <- textProcessor(documents, metadata = metadata) 
  } else { 
    processed <- textProcessor(documents)
  }
  
  
  # TODO experiment with `lower.thresh` arg to prepDocuments
  # plotRemoved(processed$documents, lower.thresh = seq(1, 200, by = 10))
  
  print("Preparing documents for modeling")
  out <- prepDocuments(processed$documents, processed$vocab, processed$meta, lower.thresh = 10)
    
  # TODO what kind of additional processing needs doing to sanity check the above? 
  # (e.g. seeing which docs were removed entirely)
  
  return(out)
}



DATA = "cogsci_papers.csv"
DATA_ALT = "cogsci_abstracts.csv"


print("Reading in ALT abstracts data")
df.abstracts.alt <- read_csv(DATA_ALT)
print("Cleaning abstracts")
df.abstracts.alt <- clean_abstracts(df.abstracts.alt)
print("Generating model framework")
processed <- textProcessor(df.abstracts.alt$abstract_cleaned, metadata = df.abstracts.alt)
# get removed docs and revise list of docs for later use getting most probable docs for a topic
removed = processed$docs.removed
new.docs = df.abstracts.alt[-removed,]

abstract.model.framework <- prepDocuments(processed$documents, processed$vocab, processed$meta, lower.thresh = 10)
#abstract.model.framework <- structure_text(df.abstracts.alt$abstract_cleaned, df.abstracts.alt) # takes < 1 min.
# Sanity checks
length(abstract.model.framework$documents)
length(abstract.model.framework$vocab)
length(abstract.model.framework$meta)
# Fit model
abstract.model.manual <- stm(documents = abstract.model.framework$documents, 
                             vocab = abstract.model.framework$vocab,
                             K = 10,
                             max.em.its = 75,
                             init.type = "Spectral") # Takes 1-2 mins.
# Validate model
labelTopics(abstract.model.manual)


print("Reading in abstracts data")
df.abstracts <- read_csv(DATA)
print("Cleaning abstracts")
df.abstracts <- clean_abstracts(df.abstracts)
print("Generating model framework")
abstract.model.framework <- structure_text(df.abstracts$abstract_cleaned, df.abstracts) # takes < 1 min.
# Sanity checks
length(abstract.model.framework$documents)
length(abstract.model.framework$vocab)
length(abstract.model.framework$meta)
# Fit model
abstract.model.manual <- stm(documents = abstract.model.framework$documents, 
                             vocab = abstract.model.framework$vocab,
                             K = 10,
                             max.em.its = 75, # Converges after ~50 iterations
                             init.type = "Spectral") # Takes 1-2 mins.
# Validate model
labelTopics(abstract.model.manual)




print("Reading in full text data :O")
df.fulltext <- read_csv(DATA)
print("Generating model framework")
#  TODO why does metadata not work?
fulltext.model.framework <- structure_text(df.fulltext$full_text) # takes up to 20 mins.
# Sanity checks
length(fulltext.model.framework$documents)
length(fulltext.model.framework$vocab)
length(fulltext.model.framework$meta)
# Fit model
fulltext.model.manual <- stm(documents = fulltext.model.framework$documents, 
                             vocab = fulltext.model.framework$vocab,
                             K = 50,
                             max.em.its = 100,
                             init.type = "Spectral") # Takes up to 10 mins.
# Validate model
labelTopics(fulltext.model.manual)

# k = 10 converges after 33 iterations
# k = 25 converges after 76 iterations
# k = 50 converges after 81 iterations





################
### MODELING ###
################

# Try out a few checks for number of topics (note this takes some time to converge)
# TODO try passing in add'l params to searchK to include prevalence and metadata
# Note this can take a while to run (> 5 mins)
topic.check = searchK(out$documents, out$vocab, K = c(5, 10, 20, 50, 100)) # add'l params for `prevalence` and `data` (metadata)
topic.check$results # compare relevant metrics for 5 and 10 topics above

# Try determining best fitting model with selectModel
# TODO try passing in add'l params here for `prevalence` and `data`
# NOTE this runs for > 10 mins and may not converge
model.select = selectModel(out$documents, 
                           out$vocab, 
                           K = 10, 
                           max.em.its = 75, 
                           runs = 20, 
                           seed = 8458159)

plotModels(model.select) # These seem pretty indistinguishable
abstract.model <- model.select$runout[[1]]

# Create the model manually rather than using the tools above to explore best fit
# TODO try passing in add'l params for `prevalence` and `data`
abstract.model.manual <- stm(documents = out$documents, 
                             vocab = out$vocab,
                             K = 10,
                             max.em.its = 75,
                             init.type = "Spectral")

#######################
### INTERPRET MODEL ###
#######################

# View the top words for each topic
labelTopics(abstract.model.manual) # this is neat, these seem relatively well-defined by top words

# View the top n documents for each topic
# TODO get this working: how to figure out which abstracts were removed during processing
topic.docs <- findThoughts(abstract.model.manual,
                           texts = new.docs$abstract_cleaned,
                           n = 3,
                           topics = c(1))


###########################
### GRAPHICAL SUMMARIES ###
###########################

cloud(stmobj = abstract.model.manual,
      topic = 1,
      type = "model",
      max.words = 25) # word cloud of most probable 25 words in topic 1
cloud(stmobj = abstract.model.manual,
      topic = 1,
      type = "documents",
      documents = abstract.model.framework$documents,
      thresh = 0.8,
      max.words = 25) # word cloud of most probable 25 words in topic 1 selected from most likely documents


plot(abstract.model, type = "summary")
plot(abstract.model, type = "perspectives", topics = c(5, 10))





DATA_ALT = "cogsci_abstracts.csv"


# Model original abstracts data
df.abstracts.alt <- read_csv(DATA_ALT)
df.abstracts.alt <- clean_abstracts(df.abstracts.alt)
abstract.model.framework <- structure_text(df.abstracts.alt$abstract_cleaned, df.abstracts.alt) # takes < 1 min.
# Fit model
abstract.model.manual <- stm(documents = abstract.model.framework$documents, 
                             vocab = abstract.model.framework$vocab,
                             K = 10,
                             max.em.its = 75, # K = 10 converges after ~25 iterations
                             init.type = "Spectral") # Takes 1-2 mins.
# Validate model
labelTopics(abstract.model.manual)
findThoughts(abstract.model.manual, texts = df.abstracts.alt$abstract_cleaned, n = 3)

# Visualize model
cloud(stmobj = abstract.model.manual,
      topic = 1,
      type = "model",
      max.words = 25) # word cloud of most probable 25 words in topic 1
cloud(stmobj = abstract.model.manual,
      topic = 1,
      type = "documents",
      documents = abstract.model.framework$documents,
      thresh = 0.8,
      max.words = 25) # word cloud of most probable 25 words in topic 1 selected from most likely documents


# Model newer abstracts data
df.abstracts <- read_csv(DATA)
df.abstracts <- clean_abstracts(df.abstracts)
abstract.model.framework <- structure_text(df.abstracts$abstract_cleaned, df.abstracts) # takes < 1 min.
# Fit model
abstract.model.manual <- stm(documents = abstract.model.framework$documents, 
                             vocab = abstract.model.framework$vocab,
                             K = 10,
                             max.em.its = 75, # K = 10 converges after ~50 iterations
                             init.type = "Spectral") # Takes 1-2 mins.
# Validate model
labelTopics(abstract.model.manual)


