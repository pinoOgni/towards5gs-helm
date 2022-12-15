# SOME USEFUL BASH COMMANDS: They should make your life easier
: '
function shenter() {
        podName=$(kubectl get po -n 5g | grep "$1" | cut -d " " -f 1)
        kubectl exec -it -n 5g $podName -- sh
}

function bashenter() {
	podName=$(kubectl get po -n 5g | grep "$1" | cut -d " " -f 1)
	kubectl exec -it -n 5g $podName -- bash
}

function logs() {
	kubectl logs -f -n 5g $(kubectl get po -n 5g | grep "$1" | cut -d " " -f 1)
}

function describe-po() {
        kubectl describe po -n 5g $(kubectl get po -n 5g | grep "$1" | cut -d " " -f 1)
}

 '