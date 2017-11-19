library(httr)
plumber200 <- POST(url = 'http://localhost:9000/test', encode = 'json',
                   body = list(n = 10, wait = 0.5))
unlist(c(api = 'plumber', status = status_code(plumber200),
         content = content(plumber200)))

rapache200 <- POST(url = 'http://localhost:7000/test', encode = 'json',
                   body = list(n = 10, wait = 0.5))
unlist(c(api = 'rApache', status = status_code(rapache200), 
         content = content(rapache200)))

rserve200 <- POST(url = 'http://localhost:8000/test', encode = 'json',
                  body = list(n = 10, wait = 0.5))
unlist(c(api = 'rserve', status = status_code(rserve200), 
         content = content(rserve200)))

rserve400 <- POST(url = 'http://localhost:8000/test', encode = 'json',
                  body = list(wait = 0.5))
unlist(c(api = 'rserve', status = status_code(rserve400), 
         content = content(rserve400)))


library(ggplot2)

performance <- read.table(
  text = '
stack	total_reqs	concurrent_reqs	avg	req_per_sec	min	p50	p75	p90	p98	p100
Rserve	150	1	506	2.0	504	510	510	510	510	536
Rserve	500	3	507	6.0	504	510	510	510	510	671
Rserve	600	6	509	12.0	503	510	510	510	540	690
rApache	150	1	511	1.9	506	510	510	520	530	605
rApache	500	3	1037	2.0	505	1000	1500	1500	1500	2523
rApache	600	6	1539	4.0	506	1500	2500	2500	2500	6397
plumber	150	1	518	1.9	512	520	520	530	540	587
plumber	500	3	1519	2.0	700	1500	1500	1500	1500	1542
plumber	600	6	3029	1.8	1543	3000	3000	3000	3100	3063\t
', sep = '\t', header = TRUE)
performance$concurrent_reqs <- as.character(performance$concurrent_reqs)

ggplot(data = performance, aes(x=concurrent_reqs, y=avg, fill=reorder(stack, avg))) +
  geom_bar(stat="identity", position=position_dodge()) + 
  labs(fill = 'stack', x = '# concurrent requests', y = 'avg response time (ms)') +
  ggtitle('Average Response Time by Concurrent Requests') + 
  theme(plot.title = element_text(hjust = 0.5))

ggplot(data = performance, aes(x=concurrent_reqs, y=p98, fill=reorder(stack, avg))) +
  geom_bar(stat="identity", position=position_dodge()) + 
  labs(fill = 'stack', x = '# concurrent requests', y = 'p98 response time (ms)') +
  ggtitle('98th Percentile Response Time by Concurrent Requests') + 
  theme(plot.title = element_text(hjust = 0.5))

ggplot(data = performance, aes(x=concurrent_reqs, y=req_per_sec, fill=reorder(stack, avg))) +
  geom_bar(stat="identity", position=position_dodge()) + 
  labs(fill = 'stack', x = '# concurrent requests', y = 'requests per second') +
  ggtitle('Requests per Second by Concurrent Requests') + 
  theme(plot.title = element_text(hjust = 0.5))
