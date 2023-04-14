---
layout: post
title: "2015-08-08-Some-Thoughts-on-Python-for-R-Users"
description: ""
category: Python
tags: [programming]
---
There seem to be growing interest in Python in the R cummunity. While there can be a range of opinions about using R over Python (or vice versa) for exploratory data analysis, fitting statistical/machine learning algorithms and so on, I consider one of the strongest attractions of using Python comes from the fact that *Python is a general purpose programming language*. As more developers are involved in, it can provide a way to get jobs done easily, which can be tricky in R. In this article, an example is introduced by illustrating how to connect to [SOAP (Simple Object Access Protocol)](https://en.wikipedia.org/wiki/SOAP) web services.

Web service (or API) is a popular way to connect to a server programmatically and SOAP web service is one type. For those who are interested in it, please see [this article](https://msdn.microsoft.com/en-us/library/ms996486.aspx). Although R has good packages to connect to a newer type of web service, which is based on [REST (Representational state transfer)](https://en.wikipedia.org/wiki/Representational_state_transfer) (eg, [httr package](https://cran.r-project.org/web/packages/httr/index.html)), I haven't found a good R package that can be used as a comprehensive SOAP client, which means I have to use the RCurl package at best. On the other hand, as 'batteries included', one of Python's philosophies, assures, it has a number of SOAP client libraries. Among those, I've chosen the [suds library](https://bitbucket.org/jurko/suds).

In this demo, I'm going to connect to [Sizmek MDX API](http://platform.mediamind.com/Eyeblaster.MediaMind.API.Doc/?v=3) where online campaign data can be pulled from it. I've used the [PyDev plugin](http://www.pydev.org/) of Eclipse and the source of this demo can be found in [my GitHub repo](https://github.com/jaehyeon-kim/sizmek_demo). It has 4 classes that connect to the API (Authentication, Advertiser, ConvTag and Campaign) and they are kept in the *sizmek* package. Also 2 extra classes are set up in the *utils* package (Soap and Helper), which keep common methods for the 4 classes. The advertiser class can be seen as following.


{% highlight r %}
from utils.soap import Soap
from datetime import datetime

class Advertiser:
    def __init__(self, pid, name, vertical, useConv):
        '''
        Constructor
        '''
        self.id = pid
        self.name = name
        self.vertical = vertical
        self.useConv = useConv
        self.addedDate = datetime.now().date()
        
    def __repr__(self):
        return "id: %s|name: %s|use conv: %s" % (self.id, self.name, self.useConv)
    
    def __str__(self):
        return "id: %s|name: %s|use conv: %s" % (self.id, self.name, self.useConv)
    
    def __len__(self):
        return 1
    
    @staticmethod
    def GetItemRes(wurl, auth, pageIndex, pageSize, showExtInfo=True):
        client = Soap.SetupClient(wurl, auth, toAddToken=True, toImportMsgSrc=True, toImportArrSrc=False)
        # update paging info
        paging = client.factory.create('ns1:ListPaging')
        paging['PageIndex'] = pageIndex
        paging['PageSize'] = pageSize
        # update filter array - empty
        filterArrary = client.factory.create('ns0:ArrayOfAdvertiserServiceFilter')
        # get response
        response = client.service.GetAdvertisers(filterArrary, paging, showExtInfo)
        return response
    
    @staticmethod
    def GetItem(response):
        objList = []
        for r in response[1]['Advertisers']['AdvertiserInfo']:
            obj = Advertiser(r['ID'], r['AdvertiserName'], r['Vertical'], r['AdvertiserExtendedInfo']['UsesConversionTags'])
            objList.append(obj)
        return objList
    
    @staticmethod
    def GetItemPgn(wurl, auth, pageIndex, pageSize, showExtInfo=True):
        objList = []
        cond = True
        while cond:
            response = Advertiser.GetItemRes(wurl, auth, pageIndex, pageSize, showExtInfo)
            objList = objList + Advertiser.GetItem(response)
            Soap.ShowProgress(response[1]['TotalCount'], len(objList), pageIndex, pageSize)
            if len(objList) < response[1]['TotalCount']:
                pageIndex += 1
            else:
                cond = False
        return objList
            
    @staticmethod
    def GetFilter(objList):
        filteredList = [obj for obj in objList if obj.useConv == True]
        print "%s out of %s advertiser where useConv equals True" % (len(filteredList), len(objList))
        return filteredList
{% endhighlight %}

The 4 classes have a number of common methods (`GetItemRes(), GetItem(), GetItemPgn(), GetFilter()`) to retrieve data from the relevant sections of the API and these methods are not related to an instance of the classes so that they are set to be static (*@staticmethod*). In R, this class may be constructed as following.


{% highlight r %}
advertiser = function(pid, name, vertical, useConv) {
  out <- list()
  out$id = pid
  out$name = name
  out$vertical = vertical
  out$useConv = useConv
  out$addedDate = Sys.Date()
  class(out) <- append(class(out), 'Advertiser')
}

GetItemRes <- function(obj) {
  UseMethod('GetItemRes', obj)
}

GetItemRes.default <- function(obj) {
  warning('Default GetItemRes method called on unrecognized object.')
  obj
}

GetItemRes.Advertiser <- function(obj) {
  response <- 'Get response from the API'
  response
}

...
{% endhighlight %}

While it is relatively straightforward to set up corresponding S3 classes, the issue is that there is no comprehensive SOAP client in R. In Python, the client library helps create a proxy class based on the relevant WSDL file so that a request/response can be handled entirely in a 'Pythonic' way. For example, below shows how to retrieve advertiser details from the API.


{% highlight r %}
from utils.helper import Helper
from sizmek.authentication import Auth
from sizmek.advertiser import Advertiser
import logging

logging.basicConfig(level=logging.INFO)
logging.getLogger('suds.client').setLevel(logging.DEBUG)

## WSDL urls
authWSDL = 'https://platform.mediamind.com/Eyeblaster.MediaMind.API/V2/AuthenticationService.svc?wsdl'
advertiserWSDL = 'https://platform.mediamind.com/Eyeblaster.MediaMind.API/V2/AdvertiserService.svc?wsdl'
campaignWSDL = 'https://platform.mediamind.com/Eyeblaster.MediaMind.API/V2/CampaignService.svc?wsdl'

## credentials
username = 'user-name'
password = 'password'
appkey = 'application-key'

## path to export API responses
path = 'C:\\projects\\workspace\\sizmek_report\\src\\csvs\\'

## authentication
auth = Auth(username, password, appkey, authWSDL)

## get advertisers
advRes = Advertiser.GetItemRes(advertiserWSDL, auth, pageIndex=0, pageSize=50, showExtInfo=True)
advList = Advertiser.GetItem(advRes)
Helper.PrintObjects(advList)

#response example
#id: 78640|name: Roses Only|use conv: True
#id: 79716|name: Knowledge Source|use conv: True
#id: 83457|name: Gold Buyers|use conv: True
{% endhighlight %}

On the other hand, if I use the RCurl package, I have to send the following SOAP message by hacking the relevant WSDL file and its XML response has to be parsed accordingly. Although it is possible, life will be a lot harder.


{% highlight r %}
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope xmlns:ns0="http://api.eyeblaster.com/message" xmlns:ns1="http://api.eyeblaster.com/message" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
   <SOAP-ENV:Header>
      <ns1:UserSecurityToken>token-generated-from-authentication-service</ns1:UserSecurityToken>
   </SOAP-ENV:Header>
   <ns1:Body xmlns:ns1="http://schemas.xmlsoap.org/soap/envelope/">
      <GetAdvertisersRequest xmlns="http://api.eyeblaster.com/message">
         <Paging>
            <PageIndex>0</PageIndex>
            <PageSize>50</PageSize>
         </Paging>
         <ShowAdvertiserExtendedInfo>true</ShowAdvertiserExtendedInfo>
      </GetAdvertisersRequest>
   </ns1:Body>
</SOAP-ENV:Envelope>
DEBUG:suds.client:headers = {'SOAPAction': '"http://api.eyeblaster.com/IAdvertiserService/GetAdvertisers"', 'Content-Type': 'text/xml; charset=utf-8'}
{% endhighlight %}

I guess most R users are not programmers but many of them are quite good at understanding how a program works. Therefore, if there is an area that R is not strong, it'd be alright to consider another language to make life easier. Among those, I consider Python is easy to learn and it can provide a range of good tools. If you're interested, please see my next article about [some thoughts on Python](http://jaehyeon-kim.github.io/python/2015/08/08/Some-Thoughts-on-Python/).

