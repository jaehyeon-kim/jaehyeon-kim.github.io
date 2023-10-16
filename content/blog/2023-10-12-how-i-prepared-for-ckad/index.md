---
title: How I Prepared for Certified Kubernetes Application Developer (CKAD)
date: 2023-10-12
draft: false
featured: false
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
# series:
#   - Kafka Development with Docker
categories:
  - General
tags: 
  - Kubernetes
  - Certification
authors:
  - JaehyeonKim
images: []
description: I recently obtained the Certified Kubernetes Application Developer (CKAD) certification.  It is for Kubernetes engineers, cloud engineers and other IT professionals responsible for building, deploying, and configuring cloud native applications with Kubernetes. In this post, I will summarise how I prepared for the exam by reviewing three online courses and two practice tests that I went through.
---

I recently obtained the [Certified Kubernetes Application Developer (CKAD)](https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/) certification. CKAD has been developed by [The Linux Foundation](https://www.linuxfoundation.org/) and the [Cloud Native Computing Foundation (CNCF)](https://www.cncf.io/), to help expand the Kubernetes ecosystem through standardized training and certification. Specifically this certification is for Kubernetes engineers, cloud engineers and other IT professionals responsible for building, deploying, and configuring cloud native applications with Kubernetes. In this post, I will summarise how I prepared for the exam by reviewing three online courses and two practice tests that I went through.

## Online Courses

I took the following courses.

- Udemy
  - [Kubernetes Certified Application Developer (CKAD) with Tests](https://www.udemy.com/course/certified-kubernetes-application-developer/)
- Cloud Academy
  - [Certified Kubernetes Application Developer (CKAD) Exam Preparation](https://cloudacademy.com/learning-paths/certified-kubernetes-application-developer-ckad-exam-preparation-1-3086/)
- A Cloud Guru
  - [Certified Kubernetes Application Developer (CKAD)](https://learn.acloud.guru/course/certified-kubernetes-application-developer)

### Udemy

I began with the *Udemy* course. The lectures are okay *individually*, and labs and practice tests are performed in an exam-like environment where questions are shown on the left side while the terminal is located on the right side. The course seems to had a major update and lots of lectures are located in the *Updates for Sep 2021 Changes* section. Those updated lectures are not according to the exam curriculum and I felt confused to figure out how they are related. Therefore, I'm not sure if the lectures are good *collectively* for those who are new to Kubernetes. Regardless its lightning labs and mock exams are quite useful. Besides, the course includes a 20% exam discount coupon, and it covers more than the course price.

### Cloud Academy

Because of the confusion, I decided to take the *Cloud Academy* course. Starting from a mini course titled *an introduction to Kubernetes*, it covers individual exam topics mostly via hands-on labs. This course was the most beneficial for me because it has a dedicated lecture for the Kubernetes command line tool (*kubectl*) and makes use of it in all labs and exam challenges. As you would have found out from other sources already, we can save a lot of time with *kubectl*, although the exam allows you to refer to the Kubernetes document site. The following lists some useful cases where the command line tool becomes beneficial significantly.

1. Creating Kubenetes resources (pod, job, cron job, deployment, service ...) with basic configurations easily (or saving their YAML manifests for further updates),
2. Saving quite some time of checking configuration objects via `kubectl explain` rather than searching the Kubenetes document, and
3. Creating a dummy resource to see how specific configurations are applied
    - e.g. for rolling update configuration of a deployment, we can create a dummy deployment and copy/paste from it

Where you're familiar with *kubectl* or not, you will be able to learn how to manage Kubenetes resources quickly and efficiently using it throughout the course, which I find one of the most important abilities for the exam. On the other hand, I think some parts of the course don't specifically match the exam scope. For example, it has a full course of Helm, and it covers way too much by ending-up creating your own helm charts. You may skip it if you just focus on the exam. Instead, you can learn from the [Introduction](https://helm.sh/docs/intro/using_helm/) section of the Helm document. 

### A Cloud Guru

A friend of mine recommended the *A Cloud Guru* course and I took it as I had a good memory while I was preparing for my [Kafka certification](/blog/2023-05-11-how-i-prepared-for-ccdak). The lectures are well-organised and matches the exam curriculum suitably. It also provides good study notes that keep key points and relevant document links. Although I enjoyed the lectures, I find quite a significant drawback of this course. The lectures and answers to hands-on labs/practice exams rely on YAML manifests, and I don't think it is a good approach for exam preparation. Nonetheless, this concise and focused course can be beneficial if you're familiar with the Kubernetes command line tool already.

## Practice Exams

### CKAD Exercises

After finishing the courses, I searched practice exams and found [CKAD exercises](https://github.com/dgkanatsios/CKAD-exercises) by Dimitris-Ilias Gkanatsios. Although the questions are grouped in the old curriculum, they do cover the current curriculum suitably as well. It also includes relevant Kubernetes document links, and you may go through them before or after attempting the questions if you'd like to learn more.

### KodeKloud

Even after I completed the CKAD exercises, I still was not sure if I was prepared enough. Luckily the KodeKloud (folks who created the Udemy course) started a free week until the 1st of October, and I took the [Ultimate Certified Kubernetes Application Developer (CKAD) Mock Exam Series](https://kodekloud.com/courses/ultimate-certified-kubernetes-application-developer-ckad-mock-exam-series/). It has a total of 10 exams and each exam has 20 questions. Not every question is new, however, some of them are repeated in later exams. The questions are quite good as I was able to practice complicated scenarios and learn more especially *Custom Resource Definition* and *Ingress*.

## Actual Exam

I was given 16 questions that requires to create/update/fix Kubernetes resources. The final question was about creating a Docker image and saving it to a local folder, which is also a part of the curriculum. For me, the questions were not tricky as the instructions were quite specific. Overall I find the level of difficulty is similar to the *CKAD exercises*. Unlike what others mention, I had 30 minutes left after I attempted all questions, and I had a chance to review all of them starting from flagged ones.

I hope you find this post useful and good luck with your exam!
