param([Parameter(Mandatory=$true)][ValidateSet('check','train','mlflow','deploy','forward','test','load','watch','status')][string]$Step)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$env:KUBECONFIG = Join-Path $PSScriptRoot '.kube\minikube-config'
$env:MINIKUBE_HOME = Join-Path $PSScriptRoot '.minikube'
$env:PATH = (Join-Path $PSScriptRoot 'tools') + ';' + $env:PATH
function Run {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}
function K { Run 'minikube' (@('-p','iris-lab','kubectl','--','--kubeconfig',$env:KUBECONFIG,'--context','iris-lab') + $args) }
switch ($Step) {
    check {
        Run 'docker' @('version')
        Run 'minikube' @('version')
        Run 'docker' @('info','--format','{{.OSType}}')
    }
    train {
        Run 'docker' @('build','--target','training','-t','iris-training:v1','.')
        Run 'docker' @('run','--rm','--mount',"type=bind,source=$PSScriptRoot,target=/app",'iris-training:v1','python','train.py')
    }
    mlflow {
        Run 'docker' @('run','--rm','-p','127.0.0.1:5000:5000','--mount',"type=bind,source=$PSScriptRoot,target=/app",'iris-training:v1','mlflow','ui','--backend-store-uri','sqlite:///mlflow.db','--host','0.0.0.0','--port','5000')
    }
    deploy {
        New-Item -ItemType Directory -Force '.kube' | Out-Null
        Run 'minikube' @('-p','iris-lab','start','--driver=docker','--cpus=2','--memory=3072')
        Run 'docker' @('build','--target','serving','-t','iris-api:v1','.')
        Run 'minikube' @('-p','iris-lab','image','load','iris-api:v1')
        K apply -f deployment.yaml
        K rollout status deployment/iris-api --timeout=180s
        Run 'minikube' @('-p','iris-lab','addons','enable','metrics-server')
        K -n kube-system rollout status deployment/metrics-server --timeout=180s
        K apply -f hpa.yaml
        K get 'pods,svc,hpa'
    }
    forward { K port-forward svc/iris-api 8080:80 }
    test {
        $body = '{"instances":[[5.1,3.5,1.4,0.2]]}'
        Invoke-RestMethod http://127.0.0.1:8080/healthz | ConvertTo-Json
        Invoke-RestMethod http://127.0.0.1:8080/predict -Method Post -ContentType 'application/json' -Body $body | ConvertTo-Json -Depth 5
    }
    load {
        K delete job iris-load --ignore-not-found
        K apply -f loadtest.yaml
        K get job iris-load
    }
    watch { K get hpa iris-api -w }
    status {
        K get 'pods,svc,hpa,jobs'
        K top pods
    }
}
