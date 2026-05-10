#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <vector>
#include <string>
#include <unordered_map>
#include <algorithm>

//Url de azure donde se guardan los resultados
#define URL_CLOUD "https://pl2api-miguel-crfxf2cqd3f3gfa4.spaincentral-01.azurewebsites.net/api/guardar"

// ============================================================
// FUNCIONES DE ENVIO AL CLOUD
// Como estamos en la máquina virtual y no puedo instalar nada uso system() y curl
// ============================================================
void enviar_al_cloud(const char* fase, const char* parametros, const char* resultado) {
    char usuario[100];
    printf("\nIntroduce tu nombre de usuario para el registro: ");
    scanf("%99s", usuario);
    while (getchar() != '\n');

    time_t ahora = time(NULL);
    char timestamp[30];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%S", localtime(&ahora));

    // Esto de aquí es el comando curl 
    // se construye el post con el JSON 
    // -s sirve para que no se muestre la salida del progreso de cómo va la función
    // -X POST sirve para indicar que es una petición post
    // -H hace falta ponerlo para que la función entienda el json, si lo quitas no funciona
    // -o NUL es para quitar la respuesta del servidor que no la vamos a usar
    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
        "curl -s -X POST \"%s\" "
        "-H \"Content-Type: application/json\" "
        "-o NUL "
        "-d \"{\\\"fase\\\":\\\"%s\\\","
        "\\\"usuario\\\":\\\"%s\\\","
        "\\\"parametros\\\":\\\"%s\\\","
        "\\\"resultado\\\":\\\"%s\\\","
        "\\\"timestamp\\\":\\\"%s\\\"}\"",
        URL_CLOUD, fase, usuario, parametros, resultado, timestamp);

    // esto escribe el curl en la terminal, si da 0 es que ha funcionado
    int ret = system(cmd);
    if (ret == 0)
        printf("\nDatos enviados correctamente.\n");
    else
        printf("\nError al enviar los datos.\n");
}

void preguntar_envio_cloud(const char* fase, const char* parametros, const char* resultado) {
    char resp;
    printf("\nDesea enviar los resultados al Cloud? (s/n): ");
    scanf(" %c", &resp);
    while (getchar() != '\n');
    if (resp == 's' || resp == 'S')
        enviar_al_cloud(fase, parametros, resultado);
}
// Lo necesitamos para la segunda fase
__constant__ int c_umbral;

int total_filas = 0;

// almacenamos cada columna en un vector, como en la guia
std::vector<float> DEP_DELAY;
std::vector<float> ARR_DELAY;
std::vector<float> WEATHER_DELAY;
std::vector<std::string> TAIL_NUM;
std::vector<std::string> ORIGIN_AIRPORT;
std::vector<std::string> DEST_AIRPORT;

void fase01_retraso_despegues();
void fase02_retraso_aterrizajes();
void fase03_reduccion_retraso();
void fase04_histograma_aeropuertos();


// lee el CSV usando indices de columna fijos del dataset Airline de Kaggle
// col 3=TAIL_NUM, 6=ORIGIN_AIRPORT, 8=DEST_AIRPORT,
//     10=DEP_DELAY,  12=ARR_DELAY,    13=WEATHER_DELAY
void leerCSV(const char* ruta) {
    FILE* fp = fopen(ruta, "r");
    if (fp == NULL) {
        printf("No se puede abrir el fichero\n");
        return;
    }

    char linea[1024];
    fgets(linea, 1024, fp); // Saltamos la cabecera

    while (fgets(linea, 1024, fp) != NULL) {
        char* t = strtok(linea, ","); //Troceamos la linea
        int col = 0;
        float dep = NAN, arr = NAN, weather = NAN; //Inicializamos como nulos los valores por si la columna esta vacia
        char tail[16] = "", origin[8] = "", dest[8] = "";

        while (t != NULL) {
            if (col == 3)  strncpy(tail, t, 15);
            else if (col == 6)  strncpy(origin, t, 7);
            else if (col == 8)  strncpy(dest, t, 7);
            else if (col == 10) dep = strlen(t) > 0 ? (float)atof(t) : NAN; //O toma un valor o ninguno
            else if (col == 12) arr = strlen(t) > 0 ? (float)atof(t) : NAN; //Sin anadir (float) aparece un warning ya que atof convierte doubles en floats
            else if (col == 13) weather = strlen(t) > 0 ? (float)atof(t) : NAN;
            col++;
            t = strtok(NULL, ","); //Siguiente trozo
        }

        // limpiamos saltos de linea que puede dejar strtok al final del ultimo campo
        tail[strcspn(tail, "\r\n")] = 0;
        origin[strcspn(origin, "\r\n")] = 0;
        dest[strcspn(dest, "\r\n")] = 0;

        DEP_DELAY.push_back(dep); //Anadimos al final el dato
        ARR_DELAY.push_back(arr);
        WEATHER_DELAY.push_back(weather);
        TAIL_NUM.push_back(tail);
        ORIGIN_AIRPORT.push_back(origin);
        DEST_AIRPORT.push_back(dest);
        total_filas++;
    }

    fclose(fp);
    printf("Dataset cargado: %d filas\n", total_filas);
}


void mostrarMenu(const char* ruta) {
    printf("\n");
    printf("=====================================================\n");
    printf("                   MENU PRINCIPAL                    \n");
    printf("=====================================================\n");
    printf("  Dataset: %s\n", ruta);
    printf("-----------------------------------------------------\n");
    printf("   1) Retraso en despegues\n");
    printf("   2) Retraso en aterrizajes\n");
    printf("   3) Reduccion de retraso (max/min)\n");
    printf("   4) Histograma de aeropuertos\n");
    printf("   5) Salir\n");
    printf("=====================================================\n");
    printf("Seleccione una opcion: ");
}

int ejecutarOpcion(int opcion, const char* ruta) {
    switch (opcion) {
    case 1:
        printf("\nHa seleccionado retraso en despegues, tenga en cuenta el signo del umbral para filtrar por adelantos o atrasos\n\n");
        fase01_retraso_despegues();
        break;
    case 2:
        printf("\nHa seleccionado retraso en aterrizajes, tenga en cuenta el signo del umbral para filtrar por adelantos o atrasos\n\n");
        fase02_retraso_aterrizajes();
        break;
    case 3:
        printf("\nHa seleccionado reduccion de retraso...\n");
        fase03_reduccion_retraso();
        break;
    case 4:
        printf("\nHa seleccionado histograma de aeropuertos...\n");
        fase04_histograma_aeropuertos();
        break;
    case 5:
        printf("\nSaliendo, por favor espere.\n");
        return 1;
    default:
        printf("\nNo ha seleccionado una de las opciones en el menu. Intentelo de nuevo.\n");
        break;
    }
    return 0;
}


// ============================================================
// FASE 01
// cada hilo mira si su vuelo supera el umbral de retraso
// umbral positivo = retrasos, umbral negativo = adelantos
// Anadimos un contador a modo de extra usando variables atomicas
// para recolectar el total de vuelos que superan el umbral
// ============================================================
__global__ void kernel_fase01(float* dep, int n, int umbral, int* contador) {
    int id = blockIdx.x * blockDim.x + threadIdx.x; // Formula del indice
    if (id >= n) return; //Corner check
    if (isnan(dep[id])) return; // Con esto eliminamos los nulos

    int tiempo = (int)dep[id]; // Con esto truncamos el decimal

    // Umbral positivo: retrasos >= umbral
    if (umbral >= 0 && tiempo >= umbral) {
        printf("- Hilo #%d: Retraso de %d minutos\n", id, tiempo);
        atomicAdd(contador, 1);
    }
    // Umbral negativo: adelantos <= umbral
    else if (umbral < 0 && tiempo <= umbral) {
        printf("- Hilo #%d: Adelanto de %d minutos\n", id, abs(tiempo)); // Ponemos valor absoluto ya que al ser negativo el valor de los adelantos para que salga de manera normal
        atomicAdd(contador, 1);
    }
}

void fase01_retraso_despegues() {
    int umbral;
    printf("Umbral positivo: Retrasos\n");
    printf("Umbral negativo: Adelantos\n\n");
    printf("Introduce el umbral en minutos: ");
    scanf("%d", &umbral);
    while (getchar() != '\n');

    //Miramos las caracteristicas del hardware para dimensionar el problema
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    int hilosPorBloque = prop.maxThreadsPerBlock;
    int numBloques = (total_filas + hilosPorBloque - 1) / hilosPorBloque; //Redondeo hacia arriba para asegurar cubrir todos los datos

    printf("GPU: %s | Bloques: %d | Hilos/bloque: %d\n\n", prop.name, numBloques, hilosPorBloque);

    float* d_dep;
    int h_contador = 0;
    int* d_contador;

    cudaMalloc(&d_contador, sizeof(int));
    cudaMemcpy(d_contador, &h_contador, sizeof(int), cudaMemcpyHostToDevice);
    cudaMalloc(&d_dep, total_filas * sizeof(float)); //Reservamos memoria
    cudaMemcpy(d_dep, DEP_DELAY.data(), total_filas * sizeof(float), cudaMemcpyHostToDevice); // Transferimos datos de CPU a GPU

    kernel_fase01 << <numBloques, hilosPorBloque >> > (d_dep, total_filas, umbral, d_contador);
    cudaDeviceSynchronize(); // Muy importante para evitar condiciones de carrera

    cudaMemcpy(&h_contador, d_contador, sizeof(int), cudaMemcpyDeviceToHost);
    printf("\nHan superado el umbral un total de %d vuelos\n", h_contador);

    //con esto preguntamos a cloud
    char params1[64], result1[64];
    snprintf(params1, sizeof(params1), "umbral=%d", umbral);
    snprintf(result1, sizeof(result1), "%d vuelos superan el umbral", h_contador);
    preguntar_envio_cloud("Fase01_Despegues", params1, result1);



    cudaFree(d_dep); //Liberas memoria
    cudaFree(d_contador);
}


// ============================================================
// FASE 02
// Usamos la arquitectura de la fase anterior, pero necesitamos
// adaptarla para anadir las matriculas
// Las matriculas son vectores de strings pero para poder escribirlos
// necesitamos pasarlo a un array de chars
// El umbral va en memoria constante (lo exige el enunciado)
// ============================================================
__global__ void kernel_fase02(float* arr, char* tail, int n,
    int* contador, char* res_tail, int* res_tiempo) {
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    if (id >= n) return;
    if (isnan(arr[id])) return;

    int tiempo = (int)arr[id];
    char* matricula = tail + id * 16; // Acceso linealizado, sigue la estructura vista en clase: fila*N+col

    if (c_umbral >= 0 && tiempo >= c_umbral) {
        printf("- Hilo #%d | Matricula: %s | Retraso: %d min\n", id, matricula, tiempo);
        int pos = atomicAdd(contador, 1); // Reservamos pos unica para el hilo
        res_tiempo[pos] = tiempo;
        // Copiamos char a char con bucle for porque strncpy no esta disponible en la GPU
        for (int j = 0; j < 16; j++)
            res_tail[pos * 16 + j] = matricula[j];
    }
    else if (c_umbral < 0 && tiempo <= c_umbral) {
        printf("- Hilo #%d | Matricula: %s | Adelanto: %d min\n", id, matricula, abs(tiempo));
        int pos = atomicAdd(contador, 1);
        res_tiempo[pos] = tiempo;
        for (int j = 0; j < 16; j++)
            res_tail[pos * 16 + j] = matricula[j];
    }
}

void fase02_retraso_aterrizajes() {

    int umbral;
    printf("Umbral positivo: Retrasos\n");
    printf("Umbral negativo: Adelantos\n\n");
    printf("Introduce el umbral en minutos: ");
    scanf("%d", &umbral);
    while (getchar() != '\n');

    cudaMemcpyToSymbol(c_umbral, &umbral, sizeof(int)); //Copiamos el umbral a memoria constante

    // La columna de las matriculas es un vector de strings, lo convertimos a array de chars para pasarlo a la GPU
    char* h_tail = new char[total_filas * 16];
    for (int i = 0; i < total_filas; i++) {
        strncpy(h_tail + i * 16, TAIL_NUM[i].c_str(), 15);
        h_tail[i * 16 + 15] = '\0';
    }

    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    int hilosPorBloque = prop.maxThreadsPerBlock;
    int numBloques = (total_filas + hilosPorBloque - 1) / hilosPorBloque;

    printf("GPU: %s | Bloques: %d | Hilos/bloque: %d\n\n", prop.name, numBloques, hilosPorBloque);

    float* d_arr;
    char* d_tail;
    int* d_contador;
    char* d_res_tail;
    int* d_res_tiempo;
    int h_contador = 0;

    cudaMalloc(&d_arr, total_filas * sizeof(float));//Reservamos memoria 
    cudaMalloc(&d_tail, total_filas * 16);
    cudaMalloc(&d_contador, sizeof(int));
    cudaMalloc(&d_res_tail, total_filas * 16);
    cudaMalloc(&d_res_tiempo, total_filas * sizeof(int));
    //Transferimos datos de CPU a GPU
    cudaMemcpy(d_arr, ARR_DELAY.data(), total_filas * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_tail, h_tail, total_filas * 16, cudaMemcpyHostToDevice);
    cudaMemcpy(d_contador, &h_contador, sizeof(int), cudaMemcpyHostToDevice);

    kernel_fase02 << <numBloques, hilosPorBloque >> > (d_arr, d_tail, total_filas, d_contador, d_res_tail, d_res_tiempo);
    cudaDeviceSynchronize();
    //Recuperamos contador y los arrays de resultados de la GPU
    cudaMemcpy(&h_contador, d_contador, sizeof(int), cudaMemcpyDeviceToHost);
    char* h_res_tail = new char[h_contador * 16];
    int* h_res_tiempo = new int[h_contador];
    cudaMemcpy(h_res_tail, d_res_tail, h_contador * 16, cudaMemcpyDeviceToHost);
    cudaMemcpy(h_res_tiempo, d_res_tiempo, h_contador * sizeof(int), cudaMemcpyDeviceToHost);

    printf("\nSe han encontrado %d aviones\n\n", h_contador);
    for (int i = 0; i < h_contador; i++) {
        if (umbral >= 0)
            printf("- Matricula %s Retraso:%d minutos\n", h_res_tail + i * 16, abs(h_res_tiempo[i]));
        else
            printf("- Matricula %s Adelanto:%d minutos\n", h_res_tail + i * 16, abs(h_res_tiempo[i]));
    }

    // Buscamos la matricula mas repetida en los resultados a modo de extra
    // Primero copiamos las matriculas a un vector para poder ordenarlas
    std::vector<std::string> lista;
    for (int i = 0; i < h_contador; i++) { //Recorre todas las matriculas guardadas en el contador
        lista.push_back(std::string(h_res_tail + i * 16));
    } // Se extrae cada matrícula y se añade al vector, tras ello lo añadimos a la lista

    std::sort(lista.begin(), lista.end()); // Ordenamos para que las matriculas iguales queden juntas, lo que evita que todos se comparen con todos dejando que se comparen tan solo con sus contiguos

    char masRepetida[16] = "";
    int maxRepeticiones = 0;
    int repeticiones = 1;

    for (int i = 1; i < h_contador; i++) {
        if (lista[i] == lista[i - 1]) {
            repeticiones++; // Si es igual a la anterior sumamos
        }
        else {
            if (repeticiones > maxRepeticiones) { // El bucle termina antes de comparar el último grupo acumulado en el contador, por lo que lo evaluamos a parte
                maxRepeticiones = repeticiones;
                // Guardamos una copia de la matrícula más repetida
                strncpy(masRepetida, lista[i - 1].c_str(), 15); // Guardamos la mas repetida hasta ahora
            }
            repeticiones = 1; // Reiniciamos para el siguiente grupo
        }
    }
    // Comprobamos el ultimo grupo que el bucle no llega a evaluar
    if (repeticiones > maxRepeticiones) { // Si las repeticiones del ultimo grupo han sido mayores que las que teníamos, lo actualizamos
                                           //en caso de no hacer esto, perderiamos al más repetido realmente, mostrando el penúltimo
        maxRepeticiones = repeticiones;
        strncpy(masRepetida, lista[h_contador - 1].c_str(), 15);
    }

    if (maxRepeticiones > 1)
        printf("\nLa matricula mas repetida ha sido: %s (%d veces)\n", masRepetida, maxRepeticiones);

    char params2[64], result2[128];
    snprintf(params2, sizeof(params2), "umbral=%d", umbral);
    snprintf(result2, sizeof(result2), "%d aviones encontrados, mas repetida: %s (%d veces)",
        h_contador, masRepetida, maxRepeticiones);
    preguntar_envio_cloud("Fase02_Aterrizajes", params2, result2);

    //Liberamos la memoria que reservamos
    cudaFree(d_arr);
    cudaFree(d_tail);
    cudaFree(d_contador);
    cudaFree(d_res_tail);
    cudaFree(d_res_tiempo);
    delete[] h_tail;
    delete[] h_res_tail;
    delete[] h_res_tiempo;
}


// funciones auxiliares para max y min porque me daba error

__device__ int calcMax(int a, int b) { return (a > b) ? a : b; }
__device__ int calcMin(int a, int b) { return (a < b) ? a : b; }

// elegimos entre calcMax o calcMin según la opción en la que estemos
__device__ int aplicarOp(int a, int b, int esMax) { return esMax ? calcMax(a, b) : calcMin(a, b); }


// ============================================================
// VARIANTE 3.1 - SIMPLE
// cada hilo aplica directamente atomicMax o atomicMin
// ============================================================
__global__ void kernel_reduccion_simple(int* datos, int n, int* resultado, int esMax) {
    int id = blockIdx.x * blockDim.x + threadIdx.x; //índice
    if (id < n) {
        if (esMax) atomicMax(resultado, datos[id]); //si el índice está en rango, se realiza una 
        else       atomicMin(resultado, datos[id]);//operación u otra según lo elegido
    }
}


// ============================================================
// VARIANTE 3.2 - BASICA
// sDatos es un array en memoria compartida
//hacemos que cada hilo cargue el dato y luego sincronizamos para esperar
// ============================================================
__global__ void kernel_reduccion_basica(int* datos, int n, int* resultado, int esMax) {
    // fijamos el tamaño al lanzar el kernel desde la CPU, un array para cada bloque
    extern __shared__ int sDatos[];

    int idGlobal = blockIdx.x * blockDim.x + threadIdx.x; // indice global 
    int idLocal = threadIdx.x;                            // indice local (el de dentro del bloque)

    // cada hilo carga su dato en la posicion que le corresponde de sDatos
    // si el hilo cae fuera del array, cargamos el neutro para no afectar al resultado
    sDatos[idLocal] = (idGlobal < n) ? datos[idGlobal] : (esMax ? INT_MIN : INT_MAX);
    __syncthreads(); // barrera: esperamos a que todos los hilos del bloque hayan cargado

    if (idGlobal < n) {
        int valor = sDatos[idLocal]; // cargamos el valor del propio hilo

        // miramos que el hilo no es el primero y puede mirar la posición anterior
        if (idLocal > 0)
            valor = aplicarOp(valor, sDatos[idLocal - 1], esMax);

        // miramos que el hilo no sea el último de los datos ni del bloque y puede mirar la siguiente
        if (idLocal + 1 < blockDim.x && idGlobal + 1 < n)
            valor = aplicarOp(valor, sDatos[idLocal + 1], esMax);

        // actualizamos el resultado global de forma atomica
        if (esMax) atomicMax(resultado, valor);
        else       atomicMin(resultado, valor);
    }
}


// ============================================================
// VARIANTE 3.3 - INTERMEDIA
// igual que la basica pero guardamos el mejor valor de cada hilo
// una segunda vez en el array y luego solo los hilos pares modifican con el atomic
// ============================================================
__global__ void kernel_reduccion_intermedia(int* datos, int n, int* resultado, int esMax) {
    //sMemoria es el array completo, luego dividido en dos mitados. sDatos la primera mitad y sValores la segunda
    extern __shared__ int sMemoria[];
    int* sDatos = sMemoria;
    int* sValores = sMemoria + blockDim.x; // mejores valores que ve cada hilo

    int idGlobal = blockIdx.x * blockDim.x + threadIdx.x;
    int idLocal = threadIdx.x;

    sDatos[idLocal] = (idGlobal < n) ? datos[idGlobal] : (esMax ? INT_MIN : INT_MAX);
    __syncthreads();

    if (idGlobal < n) {//aquí misma lógica que antes, nos quedamos con el valor primero y miramos que
        //pueda mirar delante y detrás.
        int valor = sDatos[idLocal];

        if (idLocal > 0)
            valor = aplicarOp(valor, sDatos[idLocal - 1], esMax);

        if (idLocal + 1 < blockDim.x && idGlobal + 1 < n)
            valor = aplicarOp(valor, sDatos[idLocal + 1], esMax);

        sValores[idLocal] = valor; //guardamos la mejor en la compartida para luego leerla con los pares
    }
    else {
        sValores[idLocal] = esMax ? INT_MIN : INT_MAX;
    }
    __syncthreads(); // esperamos a haber cargado los mejores

    // los pares miran su valor y el del siguiente hilo y se quedan con el mejor para hacer la atómica
    if (idGlobal < n && (idLocal % 2 == 0)) {
        int valor = sValores[idLocal];
        if (idLocal + 1 < blockDim.x && idGlobal + 1 < n)
            valor = aplicarOp(valor, sValores[idLocal + 1], esMax);
        if (esMax) atomicMax(resultado, valor);
        else       atomicMin(resultado, valor);
    }
}


// ============================================================
// VARIANTE 3.4 - PATRON DE REDUCCION
// reduccion en arbol, en cada paso reducimos el problema 
// los hilos con idLocal menor que paso combinan su posicion con la
// que esta a distancia justamente paso, 
// hasta que el resultado se guarda en la primera posición de la estructura,
//  y luego el primer hilo la escribe como resuk
// se repite con un kernel tras otro hasta 10 o menos valores, y la CPU termina
// ============================================================
__global__ void kernel_reduccion_patron(int* entrada, int* salida, int n, int esMax) {
    extern __shared__ int sDatos[]; // memoria compartida del bloque

    int idLocal = threadIdx.x;                            // indice local
    int idGlobal = blockIdx.x * blockDim.x + threadIdx.x; // indice global

    // cada hilo carga su dato 
    sDatos[idLocal] = (idGlobal < n) ? entrada[idGlobal] : (esMax ? INT_MIN : INT_MAX);
    __syncthreads();

    // reduccion en arbol binario: cada paso se divide por 2
    // solo consideramos los hilos cuya idlocal sea menor que el tamaño del paso, es decir la primera mitad
    for (int paso = blockDim.x / 2; paso > 0; paso >>= 1) {
        if (idLocal < paso)
            sDatos[idLocal] = aplicarOp(sDatos[idLocal], sDatos[idLocal + paso], esMax);
        __syncthreads(); // sincronizamos para esperar
    }

    // al terminar el bucle, el minimo o máximo está en la primera posición del array
    if (idLocal == 0) salida[blockIdx.x] = sDatos[0];
}


// ============================================================
// FASE 03 - REDUCCION
// calcula el max o min de una columna con 4 variantes distintas
// ============================================================
void fase03_reduccion_retraso() {
    if (total_filas == 0) {
        printf("Error: no hay datos cargados\n");
        return;
    }

    int opcionColumna, opcionTipo, opcionVariante;

    printf("Columna:\n  [1] DEP_DELAY\n  [2] ARR_DELAY\n  [3] WEATHER_DELAY\nOpcion: ");
    scanf("%d", &opcionColumna);

    printf("Tipo:\n  [1] Maximo\n  [2] Minimo\nOpcion: ");
    scanf("%d", &opcionTipo);

    printf("Variante:\n  [1] Simple\n  [2] Basica\n  [3] Intermedia\n  [4] Patron\nOpcion: ");
    scanf("%d", &opcionVariante);
    while (getchar() != '\n');

    std::vector<float>* columna = NULL;
    const char* nombreColumna = "";

    switch (opcionColumna) {
    case 1: columna = &DEP_DELAY;     nombreColumna = "DEP_DELAY";     break;
    case 2: columna = &ARR_DELAY;     nombreColumna = "ARR_DELAY";     break;
    case 3: columna = &WEATHER_DELAY; nombreColumna = "WEATHER_DELAY"; break;
    default:
        printf("Columna no valida\n");
        return;
    }

    int esMax = (opcionTipo == 1) ? 1 : 0;
    const char* nombreTipo = esMax ? "MAXIMO" : "MINIMO";

    // consultamos las caracteristicas de la GPU para calcular hilos y bloques
    // limito a 512 porque el desborde me ha hecho crashear

    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    int hilosPorBloque = min(prop.maxThreadsPerBlock, 512);

    int n = (int)columna->size();
    int numBloques = (n + hilosPorBloque - 1) / hilosPorBloque;

    // convertir floats a int truncando y reemplazo NAN por valor neutro
    int* h_datos = (int*)malloc(n * sizeof(int));
    int validos = 0;
    for (int i = 0; i < n; i++) {
        float v = (*columna)[i];
        if (isnan(v))
            h_datos[i] = esMax ? INT_MIN : INT_MAX;
        else {
            h_datos[i] = (int)v;
            validos++;
        }
    }

    printf("Valores validos en %s: %d / %d\n", nombreColumna, validos, n);
    printf("Columna: %s | Op: %s | Variante: %d\n", nombreColumna, nombreTipo, opcionVariante);
    printf("GPU: %s | Bloques: %d | Hilos/bloque: %d\n", prop.name, numBloques, hilosPorBloque);

    int* d_datos = NULL;
    cudaMalloc((void**)&d_datos, n * sizeof(int));
    cudaMemcpy(d_datos, h_datos, n * sizeof(int), cudaMemcpyHostToDevice);

    int h_resultado = esMax ? INT_MIN : INT_MAX;
    int* d_resultado = NULL;
    cudaMalloc((void**)&d_resultado, sizeof(int));
    cudaMemcpy(d_resultado, &h_resultado, sizeof(int), cudaMemcpyHostToDevice);

    if (opcionVariante == 1) {
        // variante simple sin memoria compartida
        kernel_reduccion_simple << <numBloques, hilosPorBloque >> > (d_datos, n, d_resultado, esMax);
        cudaDeviceSynchronize();
        cudaMemcpy(&h_resultado, d_resultado, sizeof(int), cudaMemcpyDeviceToHost);
        printf("[RESULTADO] %s de %s = %d\n", nombreTipo, nombreColumna, h_resultado);
    }
    else if (opcionVariante == 2) {
        // variante basica 
        size_t tamanoCompartida = hilosPorBloque * sizeof(int);
        kernel_reduccion_basica << <numBloques, hilosPorBloque, tamanoCompartida >> > (d_datos, n, d_resultado, esMax);
        cudaDeviceSynchronize();
        cudaMemcpy(&h_resultado, d_resultado, sizeof(int), cudaMemcpyDeviceToHost);
        printf("[RESULTADO] %s de %s = %d\n", nombreTipo, nombreColumna, h_resultado);
    }
    else if (opcionVariante == 3) {
        // variante intermedia: 
        size_t tamanoCompartida = 2 * hilosPorBloque * sizeof(int);
        kernel_reduccion_intermedia << <numBloques, hilosPorBloque, tamanoCompartida >> > (d_datos, n, d_resultado, esMax);
        cudaDeviceSynchronize();
        cudaMemcpy(&h_resultado, d_resultado, sizeof(int), cudaMemcpyDeviceToHost);
        printf("[RESULTADO] %s de %s = %d\n", nombreTipo, nombreColumna, h_resultado);
    }
    else if (opcionVariante == 4) {
        // reduccion con los pasos
        int nActual = n;
        int* d_entrada = d_datos;
        int* d_salida = NULL;
        bool liberarEntrada = false;

        while (1) {
            int bloquesActuales = (nActual + hilosPorBloque - 1) / hilosPorBloque;
            size_t tamanoCompartida = hilosPorBloque * sizeof(int);
            cudaMalloc((void**)&d_salida, bloquesActuales * sizeof(int));

            kernel_reduccion_patron << <bloquesActuales, hilosPorBloque, tamanoCompartida >> > (d_entrada, d_salida, nActual, esMax);
            cudaDeviceSynchronize();

            if (liberarEntrada) cudaFree(d_entrada);

            if (bloquesActuales <= 10) {
                int* h_parciales = (int*)malloc(bloquesActuales * sizeof(int));
                cudaMemcpy(h_parciales, d_salida, bloquesActuales * sizeof(int), cudaMemcpyDeviceToHost);

                h_resultado = h_parciales[0];
                for (int i = 1; i < bloquesActuales; i++) {
                    h_resultado = esMax
                        ? ((h_resultado > h_parciales[i]) ? h_resultado : h_parciales[i])
                        : ((h_resultado < h_parciales[i]) ? h_resultado : h_parciales[i]);
                }

                free(h_parciales);
                cudaFree(d_salida);
                break;
            }

            d_entrada = d_salida;
            nActual = bloquesActuales;
            liberarEntrada = true;
        }

        printf("[RESULTADO] %s de %s = %d\n", nombreTipo, nombreColumna, h_resultado);
    }
    else {
        printf("Variante no valida\n");
    }

    char params3[128], result3[64];
    snprintf(params3, sizeof(params3), "columna=%s tipo=%s variante=%d",
        nombreColumna, nombreTipo, opcionVariante);
    snprintf(result3, sizeof(result3), "%s=%d", nombreTipo, h_resultado);
    preguntar_envio_cloud("Fase03_Reduccion", params3, result3);

    cudaFree(d_resultado);
    cudaFree(d_datos);
    free(h_datos);
}


// ============================================================
// FASE 04 - HISTOGRAMA DE AEROPUERTOS
// contamos cuantos vuelos pasan por cada aeropuerto
// la idea es convertir los strings a IDs numericos en CPU
// y luego contar con atomicAdd en GPU (mucho mas eficiente que
// manipular strings directamente en la GPU)
// ============================================================

// kernel: cada hilo suma 1 al contador de su aeropuerto
__global__ void kernel_histograma(int* ids, int n, int* contadores, int numAeropuertos) {
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    if (id >= n) return;

    int idx = ids[id];
    if (idx >= 0 && idx < numAeropuertos) {
        atomicAdd(&contadores[idx], 1);
    }
}

void fase04_histograma_aeropuertos() {
    if (total_filas == 0) {
        printf("Error: no hay datos\n");
        return;
    }

    int opcionTipo, umbral;

    printf("Tipo de aeropuerto:\n  [1] Origen\n  [2] Destino\nOpcion: ");
    scanf("%d", &opcionTipo);

    printf("Umbral minimo de vuelos para mostrar: ");
    scanf("%d", &umbral);
    while (getchar() != '\n');

    std::vector<std::string>* columna = (opcionTipo == 1) ? &ORIGIN_AIRPORT : &DEST_AIRPORT;
    const char* nombreColumna = (opcionTipo == 1) ? "ORIGIN_AIRPORT" : "DEST_AIRPORT";

    // construir el mapa aeropuerto->id en CPU
    std::unordered_map<std::string, int> mapaAeropuertos;
    std::vector<std::string> listaAeropuertos;

    for (int i = 0; i < total_filas; i++) {
        const std::string& codigo = (*columna)[i];
        if (codigo.empty()) continue;
        if (mapaAeropuertos.find(codigo) == mapaAeropuertos.end()) {
            mapaAeropuertos[codigo] = (int)listaAeropuertos.size();
            listaAeropuertos.push_back(codigo);
        }
    }

    int numAeropuertos = (int)listaAeropuertos.size();
    printf("Aeropuertos unicos en %s: %d\n", nombreColumna, numAeropuertos);

    // convertir la columna de strings a array de IDs enteros
    int* h_ids = new int[total_filas];
    for (int i = 0; i < total_filas; i++) {
        const std::string& codigo = (*columna)[i];
        h_ids[i] = codigo.empty() ? -1 : mapaAeropuertos[codigo];
    }

    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    int hilosPorBloque = prop.maxThreadsPerBlock;
    int numBloques = (total_filas + hilosPorBloque - 1) / hilosPorBloque;

    printf("GPU: %s | Bloques: %d | Hilos/bloque: %d\n\n", prop.name, numBloques, hilosPorBloque);

    int* d_ids;
    int* d_contadores;

    cudaMalloc(&d_ids, total_filas * sizeof(int));
    cudaMalloc(&d_contadores, numAeropuertos * sizeof(int));

    cudaMemcpy(d_ids, h_ids, total_filas * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemset(d_contadores, 0, numAeropuertos * sizeof(int)); // inicializar a 0

    kernel_histograma << <numBloques, hilosPorBloque >> > (d_ids, total_filas, d_contadores, numAeropuertos);
    cudaDeviceSynchronize();

    int* h_contadores = new int[numAeropuertos];
    cudaMemcpy(h_contadores, d_contadores, numAeropuertos * sizeof(int), cudaMemcpyDeviceToHost);

    // ordenar por numero de vuelos (de mayor a menor) y filtrar por umbral
    std::vector<std::pair<int, int>> ranking;
    for (int i = 0; i < numAeropuertos; i++) {
        if (h_contadores[i] >= umbral)
            ranking.push_back(std::make_pair(h_contadores[i], i));
    }
    std::sort(ranking.begin(), ranking.end(),
        [](const std::pair<int, int>& a, const std::pair<int, int>& b) {
            return a.first > b.first;
        });

    printf("Histograma de %s (umbral >= %d):\n\n", nombreColumna, umbral);
    printf("  %-6s | %8s | Histograma\n", "Codigo", "Vuelos");
    printf("  ------+----------+------------------------------------------\n");

    int maxConteo = ranking.empty() ? 1 : ranking[0].first;
    const int MAX_BARRAS = 40;

    for (size_t k = 0; k < ranking.size(); k++) {
        int conteo = ranking[k].first;
        int idx = ranking[k].second;
        int barras = (int)((float)conteo / maxConteo * MAX_BARRAS);

        printf("  %-6s | %8d | ", listaAeropuertos[idx].c_str(), conteo);
        for (int b = 0; b < barras; b++) printf("#");
        printf("\n");
    }

    printf("\nAeropuertos mostrados: %d de %d (umbral >= %d)\n",
        (int)ranking.size(), numAeropuertos, umbral);

    char params4[64], result4[64];
    snprintf(params4, sizeof(params4), "tipo=%s umbral=%d", nombreColumna, umbral);
    snprintf(result4, sizeof(result4), "%d aeropuertos mostrados de %d",
        (int)ranking.size(), numAeropuertos);
    preguntar_envio_cloud("Fase04_Histograma", params4, result4);

    cudaFree(d_ids);
    cudaFree(d_contadores);
    delete[] h_ids;
    delete[] h_contadores;
}


// ============================================================
// MAIN
// ============================================================
int main() {
    char ruta[1024];
    const char* ruta_defecto = "C:\\Users\\miguel.lujan\\Downloads\\Airline_dataset.csv";

    // bucle hasta que se cargue un dataset valido
    int cargado = 0;
    while (!cargado) {
        printf("(Pulse Intro para usar la ruta por defecto: %s)\n\n", ruta_defecto);
        printf("Formato de ruta: C:\\Users\\nombre\\carpeta\\archivo.csv\n");
        printf("Introduzca la ruta base del dataset:\n");

        fgets(ruta, 1024, stdin);

        if (ruta[0] == '\n') {
            strcpy(ruta, ruta_defecto);
            printf("Usando ruta por defecto.\n");
        }
        else {
            ruta[strcspn(ruta, "\n")] = 0;
        }

        printf("Ruta seleccionada: %s\n", ruta);
        printf("\nCargando dataset, por favor espere.\n");
        leerCSV(ruta);

        if (total_filas == 0) {
            printf("\n[ERROR] No se cargaron datos. Comprueba que la ruta es correcta y el fichero existe.\n");
            printf("Ejemplo valido: C:\\Users\\nombre\\Desktop\\Airline_dataset.csv\n\n");
        }
        else {
            cargado = 1;
        }
    }

    int opcion;
    int salir = 0;

    while (!salir) {
        mostrarMenu(ruta);

        if (scanf("%d", &opcion) != 1) {
            while (getchar() != '\n');  // limpiar buffer si entrada invalida
            printf("Entrada invalida, has de introducir un numero.\n");
            continue;
        }

        while (getchar() != '\n');      // limpiar el '\n' residual del scanf
        salir = ejecutarOpcion(opcion, ruta);
    }

    return 0;
}
