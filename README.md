# SAisig
**SAisig** is an iOS project that detects inappropriate images  and replaces them with a black placeholder, ensuring a safe social media experience.   This project is based on the [GantMan/nsfw_model](https://github.com/GantMan/nsfw_model) repository.  

---


- Analyze images displayed in the app using a CoreML model.  
- Automatically replace inappropriate images with a black image.  
- Provide a safe and clean user experience.  

---


1. `UIImageView` is swizzled to intercept `setImage:` calls.  
2. Each image is checked asynchronously with the CoreML model.  
3. If the image is classified as inappropriate, it is replaced with a solid black image.  
4. Safe images are displayed normally.  

---


- **Objective-C (UIKit)**  
- **CoreML** for image classification  
- **NSFW Model by GantMan** → converted from `.h5` → `.mlmodel` → `.mlmodelc`  

---


The NSFW classification model is from [GantMan/nsfw_model](https://github.com/GantMan/nsfw_model).  
The model was converted from **Keras (.h5)** to **CoreML (.mlmodel)** and then compiled into **.mlmodelc** for use in this project.  

---


1. Add the compiled `SafeModel.mlmodelc` file into the `Documents/` directory of your app.  
2. Build and run the project in Theos.  
3. All `UIImageView` instances in your app will now automatically be filtered for safe content.  
