#version 120

const int shadowMapResolution = 1024;   // 阴影分辨率 默认 1024
const float	sunPathRotation	= -40.0;    // 太阳偏移角 默认 0
const int noiseTextureResolution = 128;     // 噪声图分辨率

uniform sampler2D texture;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadow;
uniform sampler2D shadowtex1;
uniform sampler2D gdepth;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D noisetex;

uniform ivec2 eyeBrightnessSmooth;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;

uniform float near;
uniform float far;  
uniform float viewWidth;
uniform float viewHeight;

uniform int worldTime;
uniform int isEyeInWater;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

varying float isNight;

varying vec3 mySkyColor;
varying vec3 mySunColor;
varying vec4 texcoord;

vec2 getFishEyeCoord(vec2 positionInNdcCoord) {
    return positionInNdcCoord / (0.15 + 0.85*length(positionInNdcCoord.xy));
}

/*
 * @function getShadow         : getShadow 渲染阴影
 * @param color                : 原始颜色
 * @param positionInWorldCoord : 该点在世界坐标系下的坐标
 * @return                     : 渲染阴影之后的颜色
 */
vec4 getShadow(vec4 color, vec4 positionInWorldCoord, float strength) {

    // 我的世界坐标 转 太阳的眼坐标
    vec4 positionInSunViewCoord = shadowModelView * positionInWorldCoord;
    // 太阳的眼坐标 转 太阳的裁剪坐标
    vec4 positionInSunClipCoord = shadowProjection * positionInSunViewCoord;
    // 太阳的裁剪坐标 转 太阳的ndc坐标
    vec4 positionInSunNdcCoord = vec4(positionInSunClipCoord.xyz/positionInSunClipCoord.w, 1.0);

    positionInSunNdcCoord.xy = getFishEyeCoord(positionInSunNdcCoord.xy);

    // 太阳的ndc坐标 转 太阳的屏幕坐标
    vec4 positionInSunScreenCoord = positionInSunNdcCoord * 0.5 + 0.5;

    float currentDepth = positionInSunScreenCoord.z;    // 当前点的深度
    float dis = length(positionInWorldCoord.xyz) / far;

    /*
    float closest = texture2D(shadow, positionInSunScreenCoord.xy).x; 
    // 如果当前点深度大于光照图中最近的点的深度 说明当前点在阴影中
    if(closest+0.0001 <= currentDepth && dis<0.99) {
        color.rgb *= 0.5;   // 涂黑
    }
    */
    
    int radius = 1;
    float sum = pow(radius*2+1, 2);
    float shadowStrength = strength * 0.6 * (1-dis) * (1-0.6*isNight); // 控制昼夜阴影强度
    for(int x=-radius; x<=radius; x++) {
        for(int y=-radius; y<=radius; y++) {
            // 采样偏移
            vec2 offset = vec2(x,y) / shadowMapResolution;
            // 光照图中最近的点的深度
            float closest = texture2D(shadowtex1, positionInSunScreenCoord.xy + offset).x;   
            // 如果当前点深度大于光照图中最近的点的深度 说明当前点在阴影中
            if(closest+0.001 <= currentDepth && dis<0.99) {
                sum -= 1; // 涂黑
            }
        }
    }
    sum /= pow(radius*2+1, 2);
    color.rgb *= sum*shadowStrength + (1-shadowStrength);  
    

    return color;
}

/* 
 *  @function getBloomOriginColor : 亮色筛选
 *  @param color                  : 原始像素颜色
 *  @return                       : 筛选后的颜色
 */
vec4 getBloomOriginColor(vec4 color) {
    float brightness = 0.299*color.r + 0.587*color.g + 0.114*color.b;
    if(brightness < 0.5) {
        color.rgb = vec3(0);
    }
    color.rgb *= (brightness-0.5)*2;
    return color;
}

/* 
 *  @function getBloom : 亮色筛选
 *  @return            : 泛光颜色
 */
vec3 getBloom() {
    int radius = 15;
    vec3 sum = vec3(0);
    
    for(int i=-radius; i<=radius; i++) {
        for(int j=-radius; j<=radius; j++) {
            vec2 offset = vec2(i/viewWidth, j/viewHeight);
            sum += getBloomOriginColor(texture2D(texture, texcoord.st+offset)).rgb;
        }
    }
    
    sum /= pow(radius+1, 2);
    return sum*0.3;
}

/*
 *  @function getBloomSource : 获取泛光原始图像
 *  @param color             : 原图像
 *  @return                  : 提取后的泛光图像
 */
vec4 getBloomSource(vec4 color) {
    // 绘制泛光
    vec4 bloom = color;
    float id = texture2D(colortex2, texcoord.st).x;
    float brightness = dot(bloom.rgb, vec3(0.2125, 0.7154, 0.0721));
    // 发光方块
    if(id==10089) {
        bloom.rgb *= 7 * vec3(2, 1, 1);
    }
    // 火把 
    else if(id==10090) {
        if(brightness<0.5) {
            bloom.rgb = vec3(0);
        }
        bloom.rgb *= 24 * pow(brightness, 2);
    }
    // 其他方块
    else {
        bloom.rgb *= brightness;
        //bloom.rgb = pow(bloom.rgb, vec3(1.0/2.2));
        //bloom.rgb = pow(bloom.rgb*4 * pow(brightness, 2), vec3(1.0/2.2));
    }
    return bloom;
}

/*
 *  @function drawSky           : 天空绘制
 *  @param color                : 原始颜色
 *  @param positionInViewCoord  : 眼坐标
 *  @param positionInWorldCoord : 我的世界坐标
 *  @return                     : 绘制天空后的颜色
 */
vec3 drawSky(vec3 color, vec4 positionInViewCoord, vec4 positionInWorldCoord) {

    // 距离
    float dis = length(positionInWorldCoord.xyz) / far;

    // 眼坐标系中的点到太阳的距离
    float disToSun = 1.0 - dot(normalize(positionInViewCoord.xyz), normalize(sunPosition));     // 太阳
    float disToMoon = 1.0 - dot(normalize(positionInViewCoord.xyz), normalize(moonPosition));    // 月亮

    // 绘制圆形太阳
    vec3 drawSun = vec3(0);
    if(disToSun<0.005 && dis>0.99999) {
        drawSun = mySunColor * 2 * (1.0-isNight);
    }
    // 绘制圆形月亮
    vec3 drawMoon = vec3(0);
    if(disToMoon<0.005 && dis>0.99999) {
        drawMoon = mySunColor * 2 * isNight;
    }
    
    // 雾和太阳颜色混合
    float sunMixFactor = clamp(1.0 - disToSun, 0, 1) * (1.0-isNight);
    vec3 finalColor = mix(mySkyColor, mySunColor, pow(sunMixFactor, 4));

    // 雾和月亮颜色混合
    float moonMixFactor = clamp(1.0 - disToMoon, 0, 1) * isNight;
    finalColor = mix(finalColor, mySunColor, pow(moonMixFactor, 4));

    // 根据距离进行最终颜色的混合
    return mix(color, finalColor, clamp(pow(dis, 3), 0, 1)) + drawSun + drawMoon;
}

/*
 *  @function drawSkyFakeReflect    : 绘制天空的假反射
 *  @param positionInViewCoord      : 眼坐标
 *  @return                         : 天空基色
 */
vec3 drawSkyFakeReflect(vec4 positionInViewCoord) {
    // 眼坐标系中的点到太阳的距离
    float disToSun = 1.0 - dot(normalize(positionInViewCoord.xyz), normalize(sunPosition));     // 太阳
    float disToMoon = 1.0 - dot(normalize(positionInViewCoord.xyz), normalize(moonPosition));    // 月亮

    // 雾和太阳颜色混合
    float sunMixFactor = clamp(1.0 - disToSun, 0, 1) * (1.0-isNight);
    vec3 finalColor = mix(mySkyColor, mySunColor, pow(sunMixFactor, 4));

    // 雾和月亮颜色混合
    float moonMixFactor = clamp(1.0 - disToMoon, 0, 1) * isNight;
    finalColor = mix(finalColor, mySunColor, pow(moonMixFactor, 4));

    return finalColor;
}

/*
 *  @function drawSkyFakeSun    : 绘制太阳的假反射
 *  @param positionInViewCoord  : 眼坐标
 *  @return                     : 太阳颜色
 */
vec3 drawSkyFakeSun(vec4 positionInViewCoord) {
    // 眼坐标系中的点到太阳的距离
    float disToSun = 1.0 - dot(normalize(positionInViewCoord.xyz), normalize(sunPosition));     // 太阳
    float disToMoon = 1.0 - dot(normalize(positionInViewCoord.xyz), normalize(moonPosition));    // 月亮

    // 绘制圆形太阳
    vec3 drawSun = vec3(0);
    if(disToSun<0.005) {
        drawSun = mySunColor * 2 * (1.0-isNight);
    }
    // 绘制圆形月亮
    vec3 drawMoon = vec3(0);
    if(disToMoon<0.005) {
        drawMoon = mySunColor * 2 * isNight;
    }

    return drawSun + drawMoon;   
}

/*
 *  @function getWave           : 绘制水面纹理
 *  @param positionInWorldCoord : 世界坐标（绝对坐标）
 *  @return                     : 纹理亮暗系数
 */
float getWave(vec4 positionInWorldCoord) {

    // 小波浪
    float speed1 = float(worldTime) / (noiseTextureResolution * 15);
    vec3 coord1 = positionInWorldCoord.xyz / noiseTextureResolution;
    coord1.x *= 3;
    coord1.x += speed1;
    coord1.z += speed1 * 0.2;
    float noise1 = texture2D(noisetex, coord1.xz).x;

    // 混合波浪
    float speed2 = float(worldTime) / (noiseTextureResolution * 7);
    vec3 coord2 = positionInWorldCoord.xyz / noiseTextureResolution;
    coord2.x *= 0.5;
    coord2.x -= speed2 * 0.15 + noise1 * 0.05;  // 加入第一个波浪的噪声
    coord2.z -= speed2 * 0.7 - noise1 * 0.05;
    float noise2 = texture2D(noisetex, coord2.xz).x;

    return noise2 * 0.6 + 0.4;
}

/*
 *  @function rayTrace  : 光线追踪计算屏幕空间反射
 *  @param startPoint   : 光线追踪起始点
 *  @param direction    : 反射光线方向
 *  @return             : 反射光线碰到的方块的颜色 -- 即反射图像颜色
 */
vec3 rayTrace(vec3 startPoint, vec3 direction) {
    vec3 point = startPoint;    // 测试点

    // 20次迭代
    int iteration = 20;
    for(int i=0; i<iteration; i++) {
        point += direction * 0.2;   // 测试点沿着反射光线方向前进

        // 眼坐标转屏幕坐标 -- 这里直接一步到位
        vec4 positionInScreenCoord = gbufferProjection * vec4(point, 1.0);
        positionInScreenCoord.xyz /= positionInScreenCoord.w;
        positionInScreenCoord.xyz = positionInScreenCoord.xyz*0.5 + 0.5;
        
        // 剔除超出屏幕空间的射线 -- 因为我们需要从屏幕空间中取颜色
        if(positionInScreenCoord.x<0 || positionInScreenCoord.x>1 ||
           positionInScreenCoord.y<0 || positionInScreenCoord.y>1) {
            return vec3(0);
        }

        // 碰撞测试
        float depth = texture2D(depthtex0, positionInScreenCoord.st).x; // 深度
        // 成功命中或者达到最大迭代次数 -- 直接返回对应的颜色
        if(depth<positionInScreenCoord.z || i==iteration-1) {
            return texture2D(texture, positionInScreenCoord.st).rgb;
        }
    }

    return vec3(0);
}

/*
 *  @function drawWater         : 水面绘制
 *  @param color                : 原颜色
 *  @param positionInWorldCoord : 我的世界坐标
 *  @param positionInViewCoord  : 眼坐标
 *  @param normal               : 眼坐标系下的法线
 *  @return                     : 绘制水面后的颜色
 *  @explain                    : 因为我太猪B了才会想到在gbuffers_water着色器中绘制水面 导致后续很难继续编程 我爬
 */
vec3 drawWater(vec3 color, vec4 positionInWorldCoord, vec4 positionInViewCoord, vec3 normal) {
    positionInWorldCoord.xyz += cameraPosition; // 转为世界坐标（绝对坐标）

    // 波浪系数
    float wave = getWave(positionInWorldCoord);
    
    /*
    vec3 finalColor = mySkyColor;
    finalColor *= wave; // 波浪纹理
    */
    
    // 按照波浪对法线进行偏移
    vec3 newNormal = normal;
    newNormal.z += 0.05 * (((wave-0.4)/0.6) * 2 - 1);
    newNormal = normalize(newNormal);

    // 计算反射光线方向
    vec3 reflectDirection = reflect(positionInViewCoord.xyz, newNormal);    

    vec3 finalColor = drawSkyFakeReflect(vec4(reflectDirection, 0)); // 假反射 -- 天空颜色
    finalColor *= wave; // 波浪纹理

    // 屏幕空间反射
    vec3 reflectColor = rayTrace(positionInViewCoord.xyz, reflectDirection);
    if(length(reflectColor)>0) {
        float fadeFactor = 1 - clamp(pow(abs(texcoord.x-0.5)*2, 2), 0, 1);
        finalColor = mix(finalColor, reflectColor, fadeFactor);
    }
    
    // 透射
    float cosine = dot(normalize(positionInViewCoord.xyz), normalize(normal));  // 计算视线和法线夹角余弦值
    cosine = clamp(abs(cosine), 0, 1);
    float factor = pow(1.0 - cosine, 4);    // 透射系数
    finalColor = mix(color, finalColor, factor);    // 透射计算

    // 假反射 -- 太阳
    finalColor += drawSkyFakeSun(vec4(reflectDirection, 0)); 

    return finalColor;
}

/*
 *  @function screenDepthToLinerDepth   : 深度缓冲转线性深度
 *  @param screenDepth                  : 深度缓冲中的深度
 *  @return                             : 真实深度 -- 以格为单位
 */
float screenDepthToLinerDepth(float screenDepth) {
    return 2 * near * far / ((far + near) - screenDepth * (far - near));
}

/*
 *  @function getUnderWaterFadeOut  : 计算水下淡出系数
 *  @param d0                       : 深度缓冲0中的原始数值
 *  @param d1                       : 深度缓冲1中的原始数值
 *  @param positionInViewCoord      : 眼坐标包不包含水面均可，因为我们将其当作视线方向向量
 *  @param normal                   : 眼坐标系下的法线
 *  @return                         : 淡出系数
 */
float getUnderWaterFadeOut(float d0, float d1, vec4 positionInViewCoord, vec3 normal) {
    // 转线性深度
    d0 = screenDepthToLinerDepth(d0);
    d1 = screenDepthToLinerDepth(d1);

    // 计算视线和法线夹角余弦值
    float cosine = dot(normalize(positionInViewCoord.xyz), normalize(normal));
    cosine = clamp(abs(cosine), 0, 1);

    return clamp(1.0 - (d1 - d0) * cosine * 0.1, 0, 1);
}

/*
 *  @function getCaustics       : 获取焦散亮度缩放倍数
 *  @param positionInWorldCoord : 当前点在 “我的世界坐标系” 下的坐标
 *  @return                     : 焦散亮暗斑纹的亮度增益
 */
float getCaustics(vec4 positionInWorldCoord) {
    positionInWorldCoord.xyz += cameraPosition; // 转为世界坐标（绝对坐标）

    // 波纹1
    float speed1 = float(worldTime) / (noiseTextureResolution * 15);
    vec3 coord1 = positionInWorldCoord.xyz / noiseTextureResolution;
    coord1.x *= 4;
    coord1.x += speed1*2 + coord1.z;
    coord1.z -= speed1;
    float noise1 = texture2D(noisetex, coord1.xz).x;
    noise1 = noise1*2 - 1.0;

    // 波纹2
    float speed2 =  float(worldTime) / (noiseTextureResolution * 15);
    vec3 coord2 = positionInWorldCoord.xyz / noiseTextureResolution;
    coord2.z *= 4;
    coord2.z += speed2*2 + coord2.x;
    coord2.x -= speed2;
    float noise2 = texture2D(noisetex, coord2.xz).x;
    noise2 = noise2*2 - 1.0;

    return noise1 + noise2; // 叠加
}


#define CLOUD_MAX_H 105.0
#define CLOUD_MIN_H 85.0
#define CLOUD_WIDTH 128.0
#define CLOUD_COLOR_BASE vec3(0.5)

// 计算 pos 点的云密度
float cloudDensity(sampler2D noisetex, vec3 pos) {
    pos.x += float(worldTime) / 5.14;

    // 高度衰减
    float mid = (CLOUD_MIN_H + CLOUD_MAX_H) / 2.0;
    float h = CLOUD_MAX_H - CLOUD_MIN_H;
    float weight = 1.0 - 2.0 * abs(mid - pos.y) / h;
    weight = pow(weight, 0.5);
    //weight *= texture2D(noisetex, vec2(pos.y, pos.y*1.34)).x * 0.4 + 0.8;

    // 采样噪声图
    vec2 coord = pos.xz * 0.00125;
    float noise = texture2D(noisetex, coord).x;
	noise += texture2D(noisetex, coord*3.5).x / 3.5;
	noise += texture2D(noisetex, coord*12.25).x / 12.25;
	noise += texture2D(noisetex, coord*42.87).x / 42.87;	
	noise /= 1.4472;
    noise *= weight;

    // 截断
    if(noise<0.45) {
        noise = 0;
    }

    return noise * 1;
}

// 屏幕深度转线性深度
float linearizeDepth(float depth) {
    return (2.0 * near) / (far + near - depth * (far - near));
}

float lum(vec3 c) {
    return dot(c, vec3(0.2, 0.7, 0.1));
}

/**/
vec4 volumeCloud(vec3 worldPos, vec3 cameraPos, vec3 sunPos, sampler2D noisetex) {

    vec4 sum = vec4(0);
    vec3 direction = normalize(worldPos - cameraPos);
    vec3 point = cameraPos;

    // 采样范围加上 CameraPos 偏移到以相机为远点的世界坐标
    float XMAX = cameraPosition.x + CLOUD_WIDTH;
    float XMIN = cameraPosition.x - CLOUD_WIDTH;
    float ZMAX = cameraPosition.z + CLOUD_WIDTH;
    float ZMIN = cameraPosition.z - CLOUD_WIDTH;

    // 如果相机在云层下，将测试起始点移动到云层底部
    if(point.y < CLOUD_MIN_H) {
        point += direction * (abs(CLOUD_MIN_H - cameraPos.y) / abs(direction.y));
    }
    // 如果相机在云层上，将测试起始点移动到云层顶部
    if(CLOUD_MAX_H < point.y) {
        point += direction * (abs(cameraPos.y - CLOUD_MAX_H) / abs(direction.y));
    }
    // 如果像素深度超过到云层距离则放弃采样
    if(length(worldPos-cameraPos) < 0.01+length(point-cameraPos)) {
        return vec4(0);
    }

    for(int i=0; i<50; i++) {        
        float rd = texture2D(noisetex, point.xz).r * 0.2 + 0.9;
        //rd = 1;
        if(i<25) {  // 前 25 次采样小步长+随机步长            
            point += direction * rd;
        } else {    // 后 25 次采样变长步长
            point += direction * (1 + float(i-25)/5.0) * rd;
        }

        // 超出采样范围则退出
        if(point.y < CLOUD_MIN_H || CLOUD_MAX_H < point.y 
        || XMIN > point.x || point.x > XMAX 
        || ZMIN > point.z || point.z > ZMAX) break;

        // 如果 raymarching hit 到物体则退出
        float pixellen = length(worldPos-cameraPos);
        float samplelen = length(point-cameraPos);
        if(samplelen > pixellen) break;

        // 采样噪声获取密度
        float density = cloudDensity(noisetex, point);

        // 向着光源进行一次采样
        vec3 L = normalize(sunPos - point);
        float density_L = cloudDensity(noisetex, point+L);
        float delta_d = clamp(density - density_L, 0, 1);
        vec3 color_L = vec3(lum(mySkyColor)) + mySunColor * 1.4 * delta_d;
        vec4 color = vec4(color_L*density, density);
        sum += color * (1.0 - sum.a);
    }

    return sum;
}


/* DRAWBUFFERS: 013 */
void main() {

    /*
    float depth = texture2D(depthtex0, texcoord.st).x;
    // 利用深度缓冲建立带深度的ndc坐标
    vec4 positionInNdcCoord = vec4(texcoord.st*2-1, depth*2-1, 1);
    // 逆投影变换 -- ndc坐标转到裁剪坐标
    vec4 positionInClipCoord = gbufferProjectionInverse * positionInNdcCoord;
    // 透视除法 -- 裁剪坐标转到眼坐标
    vec4 positionInViewCoord = vec4(positionInClipCoord.xyz/positionInClipCoord.w, 1.0);
    // 逆 “视图模型” 变换 -- 眼坐标转 “我的世界坐标” 
    vec4 positionInWorldCoord = gbufferModelViewInverse * positionInViewCoord;
    */

    // 带水面方块的坐标转换
    float depth0 = texture2D(depthtex0, texcoord.st).x;
    vec4 positionInNdcCoord0 = vec4(texcoord.st*2-1, depth0*2-1, 1);
    vec4 positionInClipCoord0 = gbufferProjectionInverse * positionInNdcCoord0;
    vec4 positionInViewCoord0 = vec4(positionInClipCoord0.xyz/positionInClipCoord0.w, 1.0);
    vec4 positionInWorldCoord0 = gbufferModelViewInverse * positionInViewCoord0;

    // 不带水面方块的坐标转换
    float depth1 = texture2D(depthtex1, texcoord.st).x;
    vec4 positionInNdcCoord1 = vec4(texcoord.st*2-1, depth1*2-1, 1);
    vec4 positionInClipCoord1 = gbufferProjectionInverse * positionInNdcCoord1;
    vec4 positionInViewCoord1 = vec4(positionInClipCoord1.xyz/positionInClipCoord1.w, 1.0);
    vec4 positionInWorldCoord1 = gbufferModelViewInverse * positionInViewCoord1;

    // 计算泛光 -- 弃用
    //color.rgb += getBloom();

    vec4 color = texture2D(texture, texcoord.st);
    float id = texture2D(colortex2, texcoord.st).x;
    vec4 temp = texture2D(colortex4, texcoord.st);
    vec3 normal = temp.xyz * 2 - 1;
    float isWater = temp.w; // 是否是水方块
    bool isStainedGlass = isWater>0 && isWater<1;  // 是否是染色玻璃
    float underWaterFadeOut = getUnderWaterFadeOut(depth0, depth1, positionInViewCoord0, normal);   // 水下淡出系数

    // 不是发光方块则绘制阴影
    if(id!=10089 && id!=10090) {
        color = getShadow(color, positionInWorldCoord1, underWaterFadeOut);
    }

    // 天空绘制
    vec3 sky = drawSky(color.rgb, positionInViewCoord1, positionInWorldCoord1);
    if(isStainedGlass) {    // 如果是染色玻璃则混合颜色
        color.rgb = mix(color.rgb, sky, 0.4) ;
    } else {    // 如果是普通方块
        color.rgb = sky;
    }

    // 焦散
    float caustics = getCaustics(positionInWorldCoord1);    // 亮暗参数  
    // 如果在水下则计算焦散
    if(isWater==1 || isEyeInWater==1) {
        color.rgb *= 1.0 + caustics*0.25 * underWaterFadeOut;
    }
    
    // 基础水面绘制
    if(isWater==1) {
        color.rgb = drawWater(color.rgb, positionInWorldCoord0, positionInViewCoord0, normal);
    }

    // 体积云
    vec4 cloud = vec4(1);
    if(texcoord.s<0.5 && texcoord.t<0.5) {

        // 用 1/4 屏幕坐标重投影到完整屏幕
        vec2 tc14 = texcoord.st * 2;
        float depth2 = texture2D(depthtex0, tc14).x;
        vec4 positionInNdcCoord2 = vec4(tc14*2-1, depth2*2-1, 1);
        vec4 positionInClipCoord2 = gbufferProjectionInverse * positionInNdcCoord2;
        vec4 positionInViewCoord2 = vec4(positionInClipCoord2.xyz/positionInClipCoord2.w, 1.0);
        vec4 positionInWorldCoord2 = gbufferModelViewInverse * positionInViewCoord2;

        vec3 sunPos = (gbufferModelViewInverse * vec4(sunPosition, 0)).xyz + cameraPosition;
        vec3 moonPos = (gbufferModelViewInverse * vec4(moonPosition, 0)).xyz + cameraPosition;
        vec3 sun = (isNight) ? moonPos : sunPos;    // 光源位置 -- 世界坐标
        vec3 worldPos = positionInWorldCoord2.xyz + cameraPosition;
        vec3 NdcPos = positionInNdcCoord2.xyz;
        cloud = volumeCloud(worldPos, cameraPosition, sun, noisetex);
    }
    //color.rgb = mix(color.rgb, cloud.rgb, clamp(cloud.a, 0, 1));
    // 体积云送 final 后处理

    gl_FragData[0] = color; // 基色
    gl_FragData[1] = getBloomSource(color); // 传递泛光原图
    gl_FragData[2] = cloud; // 传递体积云
}