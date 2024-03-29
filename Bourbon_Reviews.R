library(rvest)
library(plyr)
library(httr)
library(RODBC)
library(openxlsx)
library(tidyverse)
library(RSelenium)
library(stringr)
library(readxl)
library(magrittr)
library(ggplot2)

# Create a tasklist of all java instances running so that we can close new instances later
before.tasklist <-  system2("tasklist", stdout = TRUE )
before.tasklist <- before.tasklist[-(1:3)]
df <- as.data.frame(before.tasklist)
df$taskname <- trimws(substr(before.tasklist, 1, 29))
df$pid <- as.integer(substr(before.tasklist, 30, 34))
df$before.tasklist <- NULL
df.java.before <- df[df$taskname == 'java.exe', ]

message(c("Start Selenium - ", format(Sys.time(), "%X")))

# Find the best version of Chrome to use based on the reported versions of Chrome and Chromedriver on THIS particular machine
chrome.version <- system2(command = "wmic",
                          args = 'datafile where name="C:\\\\Program Files (x86)\\\\Google\\\\Chrome\\\\Application\\\\chrome.exe" get Version /value',
                          stdout = TRUE,
                          stderr = TRUE) %>%
                          stringr::str_extract(pattern = "(?<=Version=)\\d+\\.\\d+\\.\\d+\\.") %>%
                          magrittr::extract(!is.na(.)) %>%
                          stringr::str_replace_all(pattern = "\\.",
                                                   replacement = "\\\\.") %>%
                          paste0("^",  .) %>%
                          stringr::str_subset(string =
                                                binman::list_versions(appname = "chromedriver") %>%
                                                dplyr::last()) %>%
                          as.numeric_version() %>%
                          max() %>%
                          as.character()
message(c("using chrome version ", chrome.version))

# Start RSelenium driver
eCaps <- list(chromeOptions = list(args = c('--disable-dev-shm-usage', '--disable-browser-side-navigation', '--no-sandbox', '--disable-gpu', '--start-maximized', '--disable-blink-features', '--disable-blink-features=AutomationControlled', '--user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.116 Safari/537.36"')))
driver <- rsDriver(browser=c("chrome"), chromever=chrome.version, extraCapabilities=eCaps)
remDr <- driver[['client']]

Sys.sleep(5)
# TEST
remDr$navigate("https://thebourbonculture.com/reviews-by-rating/")
Sys.sleep(9)

# Create a tasklist of all java instances running now, after starting Selenium
after.tasklist <-  system2("tasklist", stdout = TRUE )
after.tasklist <- after.tasklist[-(1:3)]
df <- as.data.frame(after.tasklist)
df$taskname <- trimws(substr(after.tasklist, 1, 29))
df$pid <- as.integer(substr(after.tasklist, 30, 34))
df$after.tasklist <- NULL
df.java.after <- df[df$taskname == 'java.exe', ]

#Find Web elements with review data
webElement.topreviews <- remDr$findElements(using = 'xpath', "//*[starts-with(text(),'1.') or starts-with(text(),'2.') or starts-with(text(),'3.') or starts-with(text(),'4.') or starts-with(text(),'5.') or starts-with(text(),'7.') or starts-with(text(),'8.') or starts-with(text(),'9.') or contains(text(),'10 - ')]")
Sys.sleep(2)
cnt <- 0
for (review in webElement.topreviews){
   cnt <- cnt + 1
   #for some reason Vance's Private Select Single Barrel Straight Bourbon was being a problem child. Just skipped haha!
   if(cnt != 191){
   rating <- as.character(review$getElementText()[[1]])
   bourbon.element <- review$findChildElement(using = 'xpath',"./child::*")
   nm <- as.character(bourbon.element$getElementText()[[1]])
   url <- as.character(bourbon.element$getElementAttribute("href")[[1]])
   print(cnt)
   print(nm)
   print(url)
   
   temp.df <- data.frame(Rating = rating,
                         Name = nm,
                         URL = url)
   
     if (cnt == 1){
       final.df <- temp.df
       print(final.df)
     }else{final.df <- rbind(temp.df,final.df)
       
     }
   }
}

#Lets clean up this dataframe
final.df <- final.df %>%
  as_tibble(.)%>%
  mutate(Rating = as.numeric(substr(Rating,1,3)))

#summarise our data by reviews
summ <- final.df %>% 
  count(Rating) %>%
  rename(QTY = n)

#Lets visualize!
ggplot(data = summ,aes(x = Rating, y = QTY)) +
  geom_bar(stat='identity')+
  scale_x_continuous(breaks = round(seq(min(summ$Rating), max(summ$Rating), by = 0.5),1)) +

#Close up shop
#Close the Driver 
remDr$close()
remDr$quit()

# Stop the Selenium server
driver$server$stop()
rm(driver)
gc()

# Compare Tasklists to find new instance(s) & kill off any new java processes spawned by this run
new.java <- subset(df.java.after, !(df.java.after$pid %in% df.java.before$pid))
for (j in 1:nrow(new.java))
{
  pid.to.kill <- as.integer(new.java$pid[j])
  message(c("Killing Pid - ", pid.to.kill))
  taskkill.cmd <- paste( "taskkill" , "/F /PID" , pid.to.kill)
  system( taskkill.cmd )
}
