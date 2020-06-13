#!/usr/bin/env bash

set -e

minikube start --vm-driver=docker -p us1 --kubernetes-version="v1.13.2" \
    --extra-config=kubelet.authentication-token-webhook=true \
    --extra-config=kubelet.authorization-mode=Webhook \
    --extra-config=scheduler.address=0.0.0.0 \
    --extra-config=controller-manager.address=0.0.0.0

minikube start --vm-driver=docker -p eu1 --kubernetes-version="v1.13.2" \
    --extra-config=kubelet.authentication-token-webhook=true \
    --extra-config=kubelet.authorization-mode=Webhook \
    --extra-config=scheduler.address=0.0.0.0 \
    --extra-config=controller-manager.address=0.0.0.0

ssh-keyscan $(minikube -p eu1 ip) >> ~/.ssh/known_hosts
ssh-keyscan $(minikube -p us1 ip) >> ~/.ssh/known_hosts
