pipeline {
  agent any

  parameters {
    string(name: 'REGISTRY', defaultValue: 'registry.example.com', description: 'Container registry hostname')
    string(name: 'IMAGE_REPOSITORY', defaultValue: 'gst-billing', description: 'Repository name in the registry')
    string(name: 'KUBECONFIG_CREDENTIALS_ID', defaultValue: 'kubeconfig-gst-billing', description: 'Jenkins file credential containing kubeconfig')
  }

  environment {
    IMAGE = "${params.REGISTRY}/${params.IMAGE_REPOSITORY}"
    KUBE_NAMESPACE = 'gst-billing'
  }

  stages {
    stage('Test') {
      steps {
        sh '''
          docker build -t "$IMAGE:test" .
          docker run --rm \
            -e DJANGO_SECRET_KEY=ci-only-not-for-runtime \
            -e POSTGRES_PASSWORD=ci-only \
            -e DJANGO_ALLOWED_HOSTS=localhost \
            "$IMAGE:test" python manage.py check
        '''
      }
    }
    stage('Build and push') {
      steps {
        script {
          env.IMAGE_TAG = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
        }
        withCredentials([usernamePassword(credentialsId: 'container-registry', usernameVariable: 'REGISTRY_USER', passwordVariable: 'REGISTRY_PASSWORD')]) {
          sh '''
            echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin
            docker build -t "$IMAGE:$IMAGE_TAG" -t "$IMAGE:latest" .
            docker push "$IMAGE:$IMAGE_TAG"
            docker push "$IMAGE:latest"
            docker logout "$REGISTRY"
          '''
        }
      }
    }
    stage('Deploy to Kubernetes') {
      steps {
        withCredentials([file(credentialsId: "${params.KUBECONFIG_CREDENTIALS_ID}", variable: 'KUBECONFIG')]) {
          sh '''
            kubectl apply -f k8s/namespace.yaml
            kubectl apply -f k8s/configmap.yaml
            kubectl apply -f k8s/postgres.yaml
            kubectl -n "$KUBE_NAMESPACE" wait --for=condition=ready pod -l app=postgres --timeout=180s
            kubectl -n "$KUBE_NAMESPACE" delete job gst-billing-migrate --ignore-not-found=true
            sed "s#registry.example.com/gst-billing:latest#$IMAGE:$IMAGE_TAG#g" k8s/migration-job.yaml | kubectl apply -f -
            kubectl -n "$KUBE_NAMESPACE" wait --for=condition=complete job/gst-billing-migrate --timeout=300s
            sed "s#registry.example.com/gst-billing:latest#$IMAGE:$IMAGE_TAG#g" k8s/app.yaml | kubectl apply -f -
            kubectl -n "$KUBE_NAMESPACE" rollout status deployment/gst-billing --timeout=300s
            kubectl apply -f k8s/ingress.yaml
          '''
        }
      }
    }
  }
}
