set -e

# Step 1: Delete Minikube and restart it
minikube delete --all
# minikube start
minikube start --mount --mount-string="/var/lib/mysql:/var/lib/mysql"

# Step 2: Configure Docker to use Minikube’s environment
# eval $(minikube -p minikube docker-env)

# Step 3: Reset 'uber' namespace
echo "🔁 Resetting 'uber' namespace..."
kubectl delete namespace uber --ignore-not-found
kubectl create namespace uber

# Step 4: Build and load Docker images
build_and_load() {
    local name=$1
    local path=$2
    # ls
    echo "🐳 Building $name Docker image..."
    cd "$path"
    docker build -t "$name:latest" .
    minikube image load "$name:latest"
    cd ..
}

build_and_load backend-api Backend
build_and_load frontend Frontend

# Step 5: Deploy Kubernetes manifests
echo "🔐 Applying secrets and deploying all services..."
kubectl apply -f k8s/ --namespace=uber
kubectl apply -f k8s/configs --namespace=uber
kubectl apply -f k8s/secrets --namespace=uber
kubectl apply -f k8s/services --namespace=uber
kubectl apply -f k8s/deployments --namespace=uber

# Step 6: Wait for deployments to become ready
deployments=(flask-backend frontend prometheus grafana loki)
for deployment in "${deployments[@]}"; do
    echo "⏳ Waiting for $deployment to become ready..."
    kubectl rollout status deployment/$deployment -n uber
done

# Step 7: Port forwarding services in the background
declare -A ports=(
    [frontend-service]=5173:80
    [flask-backend]=5000:5000
    [prometheus]=9090:9090
    [grafana]=3000:3000
    [loki]=3100:3100
)

echo "🔗 Setting up port forwarding..."
for service in "${!ports[@]}"; do
    kubectl port-forward svc/$service ${ports[$service]} -n uber &
done

# Step 8: Print service access URLs
echo ""
echo "🌐 To access your services, use the following commands:"
for service in "prometheus grafana flask-backend frontend-service"; do
    echo "🟢 $service:"
    echo "minikube service $service -n uber --url"
    echo ""
done

echo "📢 If using Vite for frontend development, run:"
echo "cd Frontend && npm run dev"
