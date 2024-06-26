# Dockerfile
FROM public.ecr.aws/h3o5n2r0/gpu-jupyter:v1.5_cuda-11.6_ubuntu-20.04_python-only

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    python3-pip \
    python3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy TensorRT tarball to the image
COPY TensorRT-8.2.4.2.Linux.x86_64-gnu.cuda-11.4.cudnn8.2.tar.gz /tmp/

# Install TensorRT
WORKDIR /tmp
RUN tar -xvzf TensorRT-8.2.4.2.Linux.x86_64-gnu.cuda-11.4.cudnn8.2.tar.gz \
    && cp -r TensorRT-8.2.4.2/include/* /usr/include/ \
    && cp -r TensorRT-8.2.4.2/lib/* /usr/lib/x86_64-linux-gnu/ \
    && rm -rf TensorRT-8.2.4.2*

# Install TensorFlow with GPU support
RUN pip install tensorflow-gpu==2.8.0

# Set the working directory
WORKDIR /workspace

# Expose Jupyter port
EXPOSE 8888

# Run Jupyter Notebook
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--allow-root", "--no-browser"]
