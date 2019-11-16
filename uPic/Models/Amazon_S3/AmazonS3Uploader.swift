//
//  AmazonS3Uploader.swift
//  uPic
//
//  Created by Svend Jin on 2019/7/28.
//  Copyright © 2019 Svend Jin. All rights reserved.
//

import Cocoa
import Alamofire
import SwiftyXMLParser

class AmazonS3Uploader: BaseUploader {

    static let shared = AmazonS3Uploader()
    static let fileExtensions: [String] = []

    func _upload(_ fileUrl: URL?, fileData: Data?, isMinio: Bool = false) {
        guard let host = ConfigManager.shared.getDefaultHost(), let data = host.data else {
            super.faild(errorMsg: "There is a problem with the map bed configuration, please check!".localized)
            return
        }

        super.start()

        let config = data as! AmazonS3HostConfig


        let bucket = config.bucket!
        let accessKey = config.accessKey!
        let secretKey = config.secretKey!
        let hostSaveKey = HostSaveKey(rawValue: config.saveKey!)!
        var domain = config.domain!
        let region = isMinio ? "US_EAST_1" : AmazonS3Region.formatRegion(config.region)
        
        if domain.hasSuffix("/") {
            domain.removeLast()
        }
        let url = isMinio ? "\(domain)/\(bucket)" : AmazonS3Util.computeUrl(bucket: bucket, region: region)

        if url.isEmpty {
            super.faild(errorMsg: "There is a problem with the map bed configuration, please check!".localized)
            return
        }

        var retData = fileData
        var fileName = ""
        var mimeType = ""
        if let fileUrl = fileUrl {
            fileName = "\(hostSaveKey.getFileName(filename: fileUrl.lastPathComponent.deletingPathExtension)).\(fileUrl.pathExtension)"
            mimeType = Util.getMimeType(pathExtension: fileUrl.pathExtension)
            retData = BaseUploaderUtil.compressImage(fileUrl)
        } else if let fileData = fileData {
            // MARK: 处理截图之类的图片，生成一个文件名
            let fileType = fileData.contentType() ?? "png"
            fileName = "\(hostSaveKey.getFileName()).\(fileType)"
            mimeType = Util.getMimeType(pathExtension: fileType)
            retData = BaseUploaderUtil.compressImage(fileData)
        } else {
            super.faild(errorMsg: "Invalid file")
            return
        }

        var key = fileName
        if (config.folder != nil && config.folder!.count > 0) {
            key = "\(config.folder!)/\(key)"
        }
        

        // MARK: 加密 policy
        let iso_date = Date().format(dateFormat: "yyyyMMdd'T'HHmmss'Z'", timeZone: TimeZone(secondsFromGMT: 0))
        let short_date = Date().format(dateFormat: "yyyyMMdd", timeZone: TimeZone(secondsFromGMT: 0))
        
        let credential = AmazonS3Util.getCredential(access_key: accessKey, short_date: short_date, region: region)
        
        var policyDict = Dictionary<String, Any>()
        let conditions: [Any] = [
            ["acl": "public-read"],
            ["bucket": bucket],
            ["starts-with", "$key", ""],
            ["x-amz-credential": credential],
            ["x-amz-algorithm": AmazonS3Util.ALGORITHM],
            ["X-amz-date": iso_date],
            ["content-type": mimeType] // 如不手动设置 content-type ， aws 默认会将文件的 content-type 设置为 binary/octet-stream 。访问时将会直接下载，而不是预览
        ]
        policyDict["conditions"] = conditions
        let policy = AmazonS3Util.getPolicy(policyDict: policyDict)

        let signature = AmazonS3Util.computeSignature(secret_key: secretKey, policy: policy, region: region, short_date: short_date)


        func multipartFormDataGen(multipartFormData: MultipartFormData) {
            multipartFormData.append(key.data(using: .utf8)!, withName: "key")
            multipartFormData.append("public-read".data(using: .utf8)!, withName: "acl")
            multipartFormData.append(credential.data(using: .utf8)!, withName: "X-Amz-Credential")
            multipartFormData.append(AmazonS3Util.ALGORITHM.data(using: .utf8)!, withName: "X-Amz-Algorithm")
            multipartFormData.append(iso_date.data(using: .utf8)!, withName: "X-Amz-Date")
            multipartFormData.append(policy.data(using: .utf8)!, withName: "policy")
            multipartFormData.append(signature.data(using: .utf8)!, withName: "X-Amz-Signature")
            // 如不手动设置 content-type ， aws 默认会将文件的 content-type 设置为 binary/octet-stream 。访问时将会直接下载，而不是预览
            multipartFormData.append(mimeType.data(using: .utf8)!, withName: "content-type")
            
            if retData != nil {
                multipartFormData.append(retData!, withName: "file", fileName: fileName, mimeType: mimeType)
            } else if fileUrl != nil {
                multipartFormData.append(fileUrl!, withName: "file", fileName: fileName, mimeType: mimeType)
            }
        }
        
        AF.upload(multipartFormData: multipartFormDataGen, to: url).validate().uploadProgress { progress in
            super.progress(percent: progress.fractionCompleted)
        }.response(completionHandler: { response -> Void in
            switch response.result {
            case .success(_):
                if (domain.isEmpty || isMinio) {
                    super.completed(url: "\(url)/\(key)\(config.suffix ?? "")")
                } else {
                    super.completed(url: "\(domain)/\(key)\(config.suffix ?? "")")
                }
            case .failure(let error):
                var errorMessage = error.localizedDescription
                if let data = response.data {
                    let xml = XML.parse(data)
                    if let errorMsg = xml.Error.Message.text {
                        errorMessage = errorMsg
                    }
                }
                super.faild(errorMsg: errorMessage)
            }
        })

    }
    
    func uploadToMinio(_ fileUrl: URL) {
        self._upload(fileUrl, fileData: nil, isMinio: true)
    }
    
    func uploadToMinio(_ fileData: Data) {
        self._upload(nil, fileData: fileData, isMinio: true)
    }

    func upload(_ fileUrl: URL) {
        self._upload(fileUrl, fileData: nil, isMinio: false)
    }

    func upload(_ fileData: Data) {
        self._upload(nil, fileData: fileData, isMinio: false)
    }
}
