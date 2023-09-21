
#include <wb.h>

#define wbCheck(stmt)                                                     \
  do {                                                                    \
    cudaError_t err = stmt;                                               \
    if (err != cudaSuccess) {                                             \
      wbLog(ERROR, "Failed to run stmt ", #stmt);                         \
      wbLog(ERROR, "Got CUDA error ...  ", cudaGetErrorString(err));      \
      return -1;                                                          \
    }                                                                     \
  } while (0)


// __device__ float 32.0 = 32.0;


// Compute C = A * B
__global__ void matrixMultiplyShared(float *A, float *B, float *C,
                                     int numARows, int numAColumns,
                                     int numBRows, int numBColumns,
                                     int numCRows, int numCColumns) {
  //@@ Insert code to implement matrix multiplication here
  //@@ You have to use shared memory for this MP
  __shared__ float subTileM[32][32];
  __shared__ float subTileN[32][32];

  int bx = blockIdx.x;
  int by = blockIdx.y;
  int tx = threadIdx.x;
  int ty = threadIdx.y;

  int Row = by * 32.0 + ty;
  int Col = bx * 32.0 + tx;
  float Pvalue = 0.0;


  for (int q = 0; q < (ceil((float)numBRows/ 32.0)); ++q) {
    if (Row < numCRows  && (q * 32.0 + tx) < numAColumns) 
      subTileM[ty][tx] = A[Row * numAColumns + (q * 32 + tx)];
    else
      subTileM[ty][tx] = 0;
    
    if (Col < numCColumns && (q * 32.0 + ty) < numBRows)
      subTileN[ty][tx] = B[(q * 32 + ty) * numBColumns + Col];
    else
      subTileN[ty][tx] = 0;
    
    __syncthreads();

    for (int k = 0; k < 32.0; ++k) {
      Pvalue += subTileM[ty][k] * subTileN[k][tx];
    }
    __syncthreads();
  }

  if (Row < numCRows && Col < numCColumns) {
    C[Row * numCColumns + Col] = Pvalue;
  }
                                  

}

int main(int argc, char **argv) {
  wbArg_t args;
  float *hostA; // The A matrix
  float *hostB; // The B matrix
  float *hostC; // The output C matrix
  float *deviceA;
  float *deviceB;
  float *deviceC;
  int numARows;    // number of rows in the matrix A
  int numAColumns; // number of columns in the matrix A
  int numBRows;    // number of rows in the matrix B
  int numBColumns; // number of columns in the matrix B
  int numCRows;    // number of rows in the matrix C (you have to set this)
  int numCColumns; // number of columns in the matrix C (you have to set
                   // this)

  args = wbArg_read(argc, argv);

  wbTime_start(Generic, "Importing data and creating memory on host");
  hostA = (float *)wbImport(wbArg_getInputFile(args, 0), &numARows,
                            &numAColumns);
  hostB = (float *)wbImport(wbArg_getInputFile(args, 1), &numBRows,
                            &numBColumns);
  //@@ Set numCRows and numCColumns
  numCRows = numARows;
  numCColumns = numBColumns;

  //@@ Allocate the hostC matrix
  int sizeC = numCRows * numCColumns * sizeof(float);
  hostC = (float *)malloc(sizeC);

  wbTime_stop(Generic, "Importing data and creating memory on host");

  wbLog(TRACE, "The dimensions of A are ", numARows, " x ", numAColumns);
  wbLog(TRACE, "The dimensions of B are ", numBRows, " x ", numBColumns);

  wbTime_start(GPU, "Allocating GPU memory.");
  //@@ Allocate GPU memory here
  int sizeA = numARows * numAColumns * sizeof(float);
  int sizeB = numBRows * numBColumns * sizeof(float);

  //cudaMalloc((address of pointer to allocated object), (size of allocated object in bytes));
  cudaMalloc((void **) &deviceA, sizeA);
  cudaMalloc((void **) &deviceB, sizeB); 
  cudaMalloc((void **) &deviceC, sizeC);

  wbTime_stop(GPU, "Allocating GPU memory.");

  wbTime_start(GPU, "Copying input memory to the GPU.");
  //@@ Copy memory to the GPU here
  cudaMemcpy(deviceA, hostA, sizeA, cudaMemcpyHostToDevice);
  cudaMemcpy(deviceB, hostB, sizeB, cudaMemcpyHostToDevice);


  wbTime_stop(GPU, "Copying input memory to the GPU.");

  //@@ Initialize the grid and block dimensions here
  dim3 DimGrid(ceil((1.0*numCColumns)/32.0), ceil((1.0*numCRows)/32.0), 1);
  dim3 DimBlock(32.0, 32.0, 1);

  wbTime_start(Compute, "Performing CUDA computation");
  //@@ Launch the GPU Kernel here
  matrixMultiplyShared<<<DimGrid, DimBlock>>>(deviceA, deviceB, deviceC, numARows, numAColumns, numBRows,
                                              numBColumns, numCRows, numCColumns);

  cudaDeviceSynchronize();
  wbTime_stop(Compute, "Performing CUDA computation");

  wbTime_start(Copy, "Copying output memory to the CPU");
  //@@ Copy the GPU memory back to the CPU here

  cudaMemcpy(hostC, deviceC, sizeC, cudaMemcpyDeviceToHost);


  wbTime_stop(Copy, "Copying output memory to the CPU");

  wbTime_start(GPU, "Freeing GPU Memory");
  //@@ Free the GPU memory here
  cudaFree(deviceA);
  cudaFree(deviceB);
  cudaFree(deviceC);

  wbTime_stop(GPU, "Freeing GPU Memory");

  wbSolution(args, hostC, numCRows, numCColumns);

  free(hostA);
  free(hostB);
  free(hostC);

  return 0;
}
