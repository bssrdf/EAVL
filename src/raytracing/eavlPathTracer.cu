#include <eavlPathTracer.h>
#include <eavl1toNScatterOp.h>
#include <eavlNto1GatherOp.h>
#include <eavlSampler.h>
#include <eavlRandOp.h>
#include <eavlMapOp.h>

eavlRayTracer::eavlRayTracer()
{

	//
	// Initialize
	//
	triGeometry = new eavlRayTriangleGeometry();
	camera = new eavlRayCamera();
	camera->setMortonSorting(false);
	rays = new eavlFullRay(camera->getWidth() * camera->getHeight());
	intersector = new eavlRayTriangleIntersector();
	scene = new eavlRTScene();
	geometryDirty = true;
	currentFrameSize = camera->getWidth() * camera->getHeight();
	frameBuffer = new eavlFloatArray("", 1, currentFrameSize * 4);
	rgbaPixels = new eavlByteArray("", 1, currentFrameSize * 4);
	depthBuffer = new eavlFloatArray("", 1, currentFrameSize);
	inShadow = new eavlIntArray("", 1, currentFrameSize);
	ambientPct = new eavlFloatArray("", 1, currentFrameSize);
    shadowX = new eavlFloatArray("",1,currentFrameSize);
    shadowY = new eavlFloatArray("",1,currentFrameSize);
    shadowZ = new eavlFloatArray("",1,currentFrameSize);
    rSurface = new eavlFloatArray("",1,currentFrameSize);                  
    gSurface = new eavlFloatArray("",1,currentFrameSize);
    bSurface = new eavlFloatArray("",1,currentFrameSize);
    lred = new eavlFloatArray("",1,currentFrameSize);               
    lgreen = new eavlFloatArray("",1,currentFrameSize);
    lblue = new eavlFloatArray("",1,currentFrameSize);
	bgColor.x = .1f;
	bgColor.y = .1f;
	bgColor.z = .1f;
	//
	// Create default color map
	//
	numColors = 2;
	float *defaultColorMap = new float[numColors * 3];
	for (int i = 0; i < numColors * 3; ++i)
	{
		defaultColorMap[i] = 1.f;
	}
	colorMap = new eavlTextureObject<float>(numColors * 3, defaultColorMap, true);

	materials = NULL;
	eavlMaterials = NULL;


	redIndexer   = new eavlArrayIndexer(4,0);
    greenIndexer = new eavlArrayIndexer(4,1);
    blueIndexer  = new eavlArrayIndexer(4,2);
    alphaIndexer = new eavlArrayIndexer(4,3);
    indexer   = new eavlArrayIndexer();

}

eavlRayTracer::~eavlRayTracer()
{
	delete colorMap;
	delete triGeometry;
	delete camera;
	delete intersector;
	delete scene;
	delete frameBuffer;
	delete rgbaPixels;
	delete depthBuffer;
	delete inShadow; 
    delete redIndexer;
    delete greenIndexer;
    delete blueIndexer;
    delete alphaIndexer;
    delete ambientPct;
    delete shadowX;
    delete shadowY;
    delete shadowZ;
    delete indexer;
    delete rSurface;
    delete gSurface;
    delete bSurface;
    delete lred;
    delete lgreen;
    delete lblue;

}


void eavlRayTracer::startScene()
{
	scene->clear();
	geometryDirty = true;
}
void eavlRayTracer::setColorMap3f(float* cmap, const int &nColors)
{
	// Colors are fed in as RGB, no alpha
	if(nColors < 1)
	{
		THROW(eavlException, "Cannot set color map size of less than 1");
	}
    delete colorMap;
    colorMap = new eavlTextureObject<float>(nColors * 3, cmap, false);
    numColors = nColors;
}

struct NormalFunctor{

    eavlTextureObject<float>  scalars;
    eavlTextureObject<float>  norms;


    NormalFunctor(eavlTextureObject<float>  *_scalars,
    			  eavlTextureObject<float>  *_norms)
        :scalars(*_scalars),
         norms(*_norms)
    {
        
    }                                                    
    EAVL_FUNCTOR tuple<float,float,float,float,float,float,float> operator()( tuple<float,  // rayOrigin x
														   						    float,  // rayOrigin y
														   						    float,  // rayOrigin z
														   						    float,  // rayDir x
														   						    float,  // rayDir y
														   						    float,  // rayDir z
														   						    float,  // hit distance
														   						    float,  // alpha
														   						    float,  // beta
														   						    int     // Hit index
														   						    > input)
    {
       
       	eavlVector3 rayOrigin(get<0>(input), get<1>(input), get<2>(input));
        eavlVector3 rayDir(get<3>(input), get<4>(input), get<5>(input));
        float hitDistance = get<6>(input);
        rayDir.normalize();
        eavlVector3 intersect = rayOrigin + hitDistance * rayDir  - EPSILON * rayDir; 

        float alpha = get<7>(input);
        float beta  = get<8>(input);
        float gamma = 1.f - alpha - beta;
        int hitIndex=get<9>(input);
        if(hitIndex == -1) return tuple<float,float,float,float,float,float,float>(0.f,0.f,0.f,0.f,0.f,0.f,0.f);
     
        eavlVector3 aNorm, bNorm, cNorm;
        aNorm.x = norms.getValue(hitIndex * 9 + 0);
        aNorm.y = norms.getValue(hitIndex * 9 + 1);
        aNorm.z = norms.getValue(hitIndex * 9 + 2);
        bNorm.x = norms.getValue(hitIndex * 9 + 3);
        bNorm.y = norms.getValue(hitIndex * 9 + 4);
        bNorm.z = norms.getValue(hitIndex * 9 + 5);
        aNorm.x = norms.getValue(hitIndex * 9 + 6);
        aNorm.y = norms.getValue(hitIndex * 9 + 7);
        aNorm.z = norms.getValue(hitIndex * 9 + 8);

        eavlVector3 normal;
        normal = aNorm*alpha + bNorm*beta + cNorm*gamma;
        float lerpedScalar = scalars.getValue(hitIndex * 3 + 0) * alpha +
        					 scalars.getValue(hitIndex * 3 + 1) * beta  + 
        					 scalars.getValue(hitIndex * 3 + 2) * gamma;
        //reflect the ray
        normal.normalize();
        if ((normal * rayDir) > 0.0f) normal = -normal; //flip the normal if we hit the back side
        return tuple<float,float,float,float,float,float,float>(normal.x, normal.y, normal.z, lerpedScalar, intersect.x, intersect.y, intersect.z);
    }
};

struct OccRayGenFunctor
{   
    int sampleNum;
    OccRayGenFunctor(int _sampleNum)
    {
        sampleNum = _sampleNum;
    }

    EAVL_FUNCTOR tuple<float,float,float> operator()(tuple<float,float,float,int>input, int seed){
        int hitIdx = get<3>(input);
        if(hitIdx == -1) tuple<float,float,float>(0.f,0.f,0.f);
        eavlVector3 normal(get<0>(input),get<1>(input),get<2>(input));
        eavlVector3 dir = eavlSampler::hemisphere<eavlSampler::HALTON>(sampleNum, seed, normal);
        return tuple<float,float,float>(dir.x,dir.y,dir.z);
    }
};


struct WorldLightingFunctor
{   
    eavlVector3 skyColor;
    WorldLightingFunctor(eavlVector3 _skyColor)
    {
        skyColor = _skyColor;
    }

    EAVL_FUNCTOR tuple<float,float,float> operator()(tuple<int,float,float,float,float,float,float>input){
        int hit = get<0>(input);
        if(hit == 1) 
        {
            eavlVector3 normal(get<1>(input), get<2>(input), get<3>(input));
            eavlVector3 dir(get<4>(input), get<5>(input), get<6>(input));
            normal.normalize();
            dir.normalize();
            float cosTheta = normal*dir; //for diffuse
            cosTheta = min(max(cosTheta,0.f),1.f); //clamp this to [0,1]
            return tuple<float,float,float>(skyColor.x * cosTheta,
                                            skyColor.y * cosTheta,
                                            skyColor.z * cosTheta);
        }
        else return tuple<float,float,float>(0.f,0.f,0.f);
    }
};

struct PhongShaderFunctor
{
    eavlVector3     light;
    eavlVector3     lightDiff;
    eavlVector3     lightSpec;

    eavlVector3     eye; 
    float           depth;
    int             colorMapSize;
    eavlVector3     bgColor;
    float4          defaultColor;

    eavlTextureObject<int>      matIds; 
    eavlFunctorArray<float>     mats;
    eavlTextureObject<float>    colorMap;
    

    PhongShaderFunctor(eavlVector3 theLight, 
    			  	   eavlVector3 eyePos, 
    			  	   eavlTextureObject<int> *_matIds, 
                  	   eavlFunctorArray<float> _mats, 
                  	   eavlTextureObject<float> *_colorMap, 
                  	   int _colorMapSize, 
                  	   eavlVector3 *_bgColor)
        : matIds(*_matIds),
          mats(_mats),
          colorMap(*_colorMap), 
          bgColor(*_bgColor)

    {
        light = theLight;
        colorMapSize = _colorMapSize;
        eye = eyePos;
        lightDiff=eavlVector3(.6,.6,.6);
        lightSpec=eavlVector3(.6,.6,.6);
       
    }

    EAVL_FUNCTOR tuple<float,float,float,float> operator()(tuple<int,  	// hit index
    													   		 int,	// shadow ray hit
    													   		 float,	// origin x 
    													   		 float,	// origin y
    													   		 float,	// origin z
    													   		 float,	// intersect x
    													   		 float,	// intersect y
    													   		 float,	// intersect z	
    													   		 float,	// normal x
    													   		 float,	// normal y
    													   		 float,	// normal z
    													   		 float, // hit scalar 
                                                                 float  // ambient occlusion percentage
    													   		 >input)
    {

        int hitIdx = get<0>(input);
        int shadowHit = get<1>(input);

        if(hitIdx == -1 ) return tuple<float,float,float,float>(bgColor.x, bgColor.y,bgColor.z,1.f); // primary ray never hit anything.
        
        eavlVector3 rayOrigin(get<2>(input),get<3>(input),get<4>(input));
        eavlVector3 rayInt(get<5>(input), get<6>(input), get<7>(input));
        eavlVector3 normal(get<8>(input), get<9>(input), get<10>(input));
        
        eavlVector3 lightDir  = light - rayInt;
        eavlVector3 viewDir   = eye - rayInt;
        
        lightDir.normalize();
        viewDir.normalize();
        
        float ambPct= get<12>(input);
    
        int id = 0;
        id = matIds.getValue(hitIdx);
        eavlVector3* matPtr = (eavlVector3*)(&mats[0]+id*12);
        eavlVector3 ka = matPtr[0];     //these could be lerped if it is possible that a single tri could be made of several mats
        eavlVector3 kd = matPtr[1];
        eavlVector3 ks = matPtr[2];
        float matShine = matPtr[3].x;

        float red   = 0.f;
        float green = 0.f;
        float blue  = 0.f;
 
 		//
        // Diffuse
 		//
        float cosTheta = normal*lightDir; //for diffuse
        cosTheta = min(max(cosTheta,0.f),1.f); //clamp this to [0,1]
        
        //
        // Specular
        //
        eavlVector3 halfVector = viewDir+lightDir;
        halfVector.normalize();
        float cosPhi = normal * halfVector;
        float specConst;
        specConst = pow(max(cosPhi,0.0f),matShine);
 
        red   = ka.x * ambPct+ (kd.x * lightDiff.x * cosTheta + ks.x * lightSpec.x * specConst) * shadowHit;
        green = ka.y * ambPct+ (kd.y * lightDiff.y * cosTheta + ks.y * lightSpec.y * specConst) * shadowHit;
        blue  = ka.z * ambPct+ (kd.z * lightDiff.z * cosTheta + ks.z * lightSpec.z * specConst) * shadowHit;
        
        /*Color map*/
        float scalar   = get<11>(input);
        int   colorIdx = max(min(colorMapSize-1, (int)floor(scalar*colorMapSize)), 0); 

        //float4 color = (colorMapSize != 2) ? colorMap->getValue(color_map_tref, colorIdx) : defaultColor; 
        float4 color;
        color.x = colorMap.getValue(colorIdx * 3 + 0); 
        color.y = colorMap.getValue(colorIdx * 3 + 1); 
        color.z = colorMap.getValue(colorIdx * 3 + 2); 
        
        red   *= color.x;
        green *= color.y;
        blue  *= color.z;
        
        
        return tuple<float,float,float,float>(min(red,1.0f),min(green,1.0f),min(blue,1.0f), 1.0f);

    }


};



void eavlRayTracer::init()
{
	

	int numRays = camera->getWidth() * camera->getHeight();
	
	if(numRays != currentFrameSize)
	{
		delete frameBuffer;
		delete rgbaPixels;
		delete depthBuffer;
		delete inShadow;

		frameBuffer = new eavlFloatArray("", 1, numRays * 4); //rgba
		rgbaPixels  = new eavlByteArray("", 1, numRays * 4); //rgba
		depthBuffer = new eavlFloatArray("", 1, numRays);
		inShadow    = new eavlIntArray("", 1, numRays);
        ambientPct = new eavlFloatArray("",1,numRays);
        shadowX = new eavlFloatArray("",1,numRays);
        shadowY = new eavlFloatArray("",1,numRays);
        shadowZ = new eavlFloatArray("",1,numRays);

        rSurface = new eavlFloatArray("",1,currentFrameSize);                  
        gSurface = new eavlFloatArray("",1,currentFrameSize);
        bSurface = new eavlFloatArray("",1,currentFrameSize);
        lred = new eavlFloatArray("",1,currentFrameSize);               
        lgreen = new eavlFloatArray("",1,currentFrameSize);
        lblue = new eavlFloatArray("",1,currentFrameSize);

        
        currentFrameSize = numRays;
	}

	if(geometryDirty)
	{
		numTriangles = scene->getNumTriangles();
		if(numTriangles > 0)
		{
			triGeometry->setVertices(scene->getTrianglePtr(), numTriangles);
			triGeometry->setScalars(scene->getTriangleScalarsPtr(), numTriangles);
			triGeometry->setNormals(scene->getTriangleNormPtr(), numTriangles);
			triGeometry->setMaterialIds(scene->getTriMatIdxsPtr(), numTriangles);
			int numMaterials = scene->getNumMaterials();
			eavlMaterials = scene->getMatsPtr();
		}
		geometryDirty = false;
	}
	
	camera->createRays(rays); //this call resets hitIndexes as well

}
void eavlRayTracer::render()
{   
	camera->printSummary();
	init();
	if(numTriangles < 1) 
	{
		//may be set the framebuffer and depthbuffer to background and infinite
		cerr<<"No trianles to render"<<endl;
		return;
	}
    if(!occlusionOn)
    {
        eavlExecutor::AddOperation(new_eavlMapOp(eavlOpArgs(ambientPct), //dummy arg
                                                 eavlOpArgs(ambientPct),
                                                 FloatMemsetFunctor(.5f)),
                                                 "setAmbient");
        eavlExecutor::Go();    
    }

   eavlExecutor::AddOperation(new_eavlMapOp(eavlOpArgs(rSurface), //dummy arg
                                            eavlOpArgs(rSurface,gSurface,bSurface),
                                            FloatMemsetFunctor3to3(0.f, 0.f, 0.f)), //this was 1.f
                                            "init");
    eavlExecutor::Go();
	
	//intersector->testIntersections(rays, INFINITE, triGeometry,1,1,camera);

	intersector->intersectionDepth(rays, INFINITE, triGeometry);
	
	eavlFunctorArray<float> mats(eavlMaterials);
	eavlExecutor::AddOperation(new_eavlMapOp(eavlOpArgs(rays->rayOriginX,
														rays->rayOriginY,
														rays->rayOriginZ,
														rays->rayDirX,
														rays->rayDirY,
														rays->rayDirZ,
														rays->distance,
														rays->alpha,
														rays->beta,
														rays->hitIdx),
                                             eavlOpArgs(rays->normalX,
                                             			rays->normalY,
                                                        rays->normalZ,
                                                        rays->scalar,
                                                        rays->intersectionX,
                                                        rays->intersectionY,
                                                        rays->intersectionZ),
                                             NormalFunctor(triGeometry->scalars,
                     									   triGeometry->normals)),
                                             "Normal functor");
    eavlExecutor::Go();

    eavlExecutor::AddOperation(new_eavlRandOp(eavlOpArgs(rays->normalX,
                                                         rays->normalY,
                                                         rays->normalZ,
                                                         rays->hitIdx),
                                                eavlOpArgs(shadowX,shadowY,shadowZ),OccRayGenFunctor(1)),
                                                "World Lighing sample");
    eavlExecutor::Go();

    intersector->intersectionOcclusion(rays, shadowX, shadowY, shadowZ, inShadow, indexer, INFINITE, triGeometry);

    eavlExecutor::AddOperation(new_eavlMapOp(eavlOpArgs(inShadow, rays->normalX, rays->normalY, rays->normalZ,
                                                        shadowX, shadowY, shadowZ),
                                             eavlOpArgs(lred, lgreen, lblue),
                                             WorldLightingFunctor(bgColor)),
                                             "wlighting");
    eavlExecutor::Go();

	intersector->intersectionShadow(rays, inShadow, lightPosition, triGeometry);	
	
    eavlExecutor::AddOperation(new_eavlMapOp(eavlOpArgs(rays->hitIdx,
														inShadow,
														rays->rayOriginX,
														rays->rayOriginY,
														rays->rayOriginZ,
														rays->intersectionX,
														rays->intersectionY,
														rays->intersectionZ,
														rays->normalX,
														rays->normalY,
														rays->normalZ,
														rays->scalar,
                                                        ambientPct),
                                             			eavlOpArgs(eavlIndexable<eavlFloatArray>(frameBuffer,*redIndexer),
                                                            	   eavlIndexable<eavlFloatArray>(frameBuffer,*greenIndexer),
                                                            	   eavlIndexable<eavlFloatArray>(frameBuffer,*blueIndexer),
                                                            	   eavlIndexable<eavlFloatArray>(frameBuffer,*alphaIndexer)),
                                             PhongShaderFunctor(lightPosition,
                                             					eavlVector3(camera->getCameraPositionX(),
                                             								camera->getCameraPositionY(),
                                             								camera->getCameraPositionZ()),
                                             					triGeometry->materialIds,
                                             					mats,
                                             					colorMap,
                                             					numColors,
                                             					&bgColor)),
                                             "Shader");
    eavlExecutor::Go();

    eavlExecutor::AddOperation(new_eavlMapOp(eavlOpArgs(eavlIndexable<eavlFloatArray>(frameBuffer,*redIndexer),
                                                        eavlIndexable<eavlFloatArray>(frameBuffer,*greenIndexer),
                                                        eavlIndexable<eavlFloatArray>(frameBuffer,*blueIndexer),
                                                        eavlIndexable<eavlFloatArray>(frameBuffer,*alphaIndexer)),
                                                 eavlOpArgs(eavlIndexable<eavlByteArray>(rgbaPixels,*redIndexer),
                                                            eavlIndexable<eavlByteArray>(rgbaPixels,*greenIndexer),
                                                            eavlIndexable<eavlByteArray>(rgbaPixels,*blueIndexer),
                                                            eavlIndexable<eavlByteArray>(rgbaPixels,*alphaIndexer)),
                                                 CopyFrameBuffer()),
                                                 "memcopy");
    eavlExecutor::Go();


}

eavlFloatArray* eavlRayTracer::getDepthBuffer(float proj22, float proj23, float proj32)
{ 
    eavlExecutor::AddOperation(new_eavlMapOp(eavlOpArgs(rays->distance), eavlOpArgs(depthBuffer), ScreenDepthFunctor(proj22, proj23, proj32)),"convertDepth");
    eavlExecutor::Go();
    return depthBuffer;
}

eavlByteArray* eavlRayTracer::getFrameBuffer() { return rgbaPixels; }

void eavlRayTracer::setDefaultMaterial(const float &ka,const float &kd, const float &ks)
{
	
      float old_a=scene->getDefaultMaterial().ka.x;
      float old_s=scene->getDefaultMaterial().ka.x;
      float old_d=scene->getDefaultMaterial().ka.x;
      if(old_a == ka && old_d == kd && old_s == ks) return;     //no change, do nothing
      scene->setDefaultMaterial(RTMaterial(eavlVector3(ka,ka,ka),
                                           eavlVector3(kd,kd,kd),
                                           eavlVector3(ks,ks,ks), 10.f,1));
}

void eavlRayTracer::setBackgroundColor(float r, float g, float b)
{
	float mn = min(r, min(g,b));
	float mx = max(r, max(g,b));
	if(mn < 0.f || mx > 1.f)
	{
		cerr<<"Invalid background color value: "<<r<<","<<g<<","<<b<<endl;
		return;
	}
	
	bgColor.x = r;
	bgColor.y = g;
	bgColor.z = b;
}




