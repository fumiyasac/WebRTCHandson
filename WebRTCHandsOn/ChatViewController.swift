//
//  ChatViewController.swift
//  WebRTCHandsOn
//
//  Created by Takumi Minamoto on 2017/05/27.
//  Copyright © 2017 tnoho. All rights reserved.
//

/**
 * ★PC側のブラウザカメラとiPhone実機側のカメラを一緒に表示するだけのサンプル
 *
 * (実装用参考資料)
 * ・WebRTCハンズオン 概要編
 * http://qiita.com/massie_g/items/916694413353a3293f73
 * ・SwiftでWebRTC実装ハンズオン 本編
 * http://qiita.com/tnoho/items/f5afa3ba749eed9b9716
 *
 * (ブラウザ側アクセス用URL)
 * おれのURLでやっているぞ！
 * https://conf.space/WebRTCHandsOn/fumiyasac
 *
 * (サーバー側実装)
 * SwiftでWebRTC実装ハンズオン用Signalingサーバ（Golang）
 * https://github.com/tnoho/WebRTCHandsOnSig
 *
 * (デバッグ用の参考資料)
 * ・WebRTCデバッグ入門
 * http://qiita.com/yusuke84/items/8d232c8d24156f16e8ba
 *
 */

import UIKit
import WebRTC
import Starscream
import SwiftyJSON

class ChatViewController: UIViewController, WebSocketDelegate, RTCPeerConnectionDelegate, RTCEAGLVideoViewDelegate {

    //WebSocketのインスタンス用のメンバ変数
    var websocket: WebSocket! = nil

    //RTCPeerConnectionFactoryのインスタンス格納用のメンバ変数
    var peerConnectionFactory: RTCPeerConnectionFactory! = nil

    //RTCpeerConnectionのインスタンス格納用のメンバ変数
    var peerConnection: RTCPeerConnection! = nil

    //VideoTrackデータ格納用のメンバ変数
    var remoteVideoTrack: RTCVideoTrack?

    //映像・音声データ格納用のメンバ変数
    var audioSource: RTCAudioSource?
    var videoSource: RTCAVFoundationVideoSource?

    //実機右上のカメラプレビュー画面
    @IBOutlet weak var cameraPreview: RTCCameraPreviewView!

    //Web側のカメラから通信を介して送られる映像を表示する画面
    @IBOutlet weak var remoteVideoView: RTCEAGLVideoView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        //RTCEAGLVideoViewDelegateプロトコル宣言
        remoteVideoView.delegate = self

        //RTCPeerConnectionFactoryの初期化
        peerConnectionFactory = RTCPeerConnectionFactory()

        //音声と映像に関する設定
        startVideo()

        //WebSocketDelegateプロトコル宣言と接続
        websocket = WebSocket(url: URL(string: "wss://conf.space/WebRTCHandsOnSig/fumiyasac")!)
        websocket.delegate = self
        websocket.connect()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    /********************
     * MARK: - deinitialize
     ********************/

    //クラスの後始末をする
    deinit {
        if peerConnection != nil {
            hangUp()
        }
        audioSource = nil
        videoSource = nil
        peerConnectionFactory = nil
    }

    /********************
     * MARK: - @IBAction
     ********************/

    //Connectボタンを押した時
    @IBAction func connectButtonAction(_ sender: Any) {

        //peerConnectionがnilの場合はオファーを作成して接続をしに行く
        if peerConnection == nil {

            //PeerConnectionを生成から相手にOfferを送るための準備
            makeOffer()

            //ログ出力
            LOG("Make offer!")

        } else {

            //ログ出力
            LOG("Peer already exist.")
        }
    }

    //HangUpボタンを押した時
    @IBAction func hangupButtonAction(_ sender: Any) {
        
        //PeerConnectionの切断
        hangUp()
    }

    //Closeボタンを押した時
    @IBAction func closeButtonAction(_ sender: Any) {

        //PeerConnectionの切断
        hangUp()

        //切断の高速化のためにこのタイミングでもwebsocketの切断をする
        websocket.disconnect()

        //起動画面に戻る
        _ = self.navigationController?.popToRootViewController(animated: true)
    }
    
    /********************
     * MARK: - WebSocketDelegate
     ********************/

    //WebSocketとの接続ができた際に呼ばれるメソッド
    func websocketDidConnect(socket: WebSocket) {
        LOG()
    }

    //WebSocketとの接続が失敗した際に呼ばれるメソッド
    func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        
        //ログ出力
        LOG("error: \(String(describing: error?.localizedDescription))")
    }
    
    //WebSocketからのメッセージ受信ができた際に呼ばれるメソッド
    func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        
        //ログ出力
        LOG("message: \(text)")
        
        //受け取ったメッセージをSwiftyJSONでJSONとしてパース
        let jsonMessage = JSON.parse(text)
        let type = jsonMessage["type"].stringValue

        //条件によって処理を分岐させる
        switch (type) {

        //answerを受け取った時の処理
        case "answer":

            //ログ出力
            LOG("Received answer ...")
            
            //JSONの値を使ってRTCSessionDescriptionを作成する
            let answer = RTCSessionDescription(type: RTCSessionDescription.type(for: type), sdp: jsonMessage["sdp"].stringValue)

            //answer情報をセットする
            setAnswer(answer)

        //candidateを受け取った時の処理
        case "candidate":

            //ログ出力
            LOG("Received ICE candidate ...")
            
            //JSONの値を使ってRTCIceCandidateを作成する
            let candidate = RTCIceCandidate(
                sdp: jsonMessage["ice"]["candidate"].stringValue,
                sdpMLineIndex:
                jsonMessage["ice"]["sdpMLineIndex"].int32Value,
                sdpMid: jsonMessage["ice"]["sdpMid"].stringValue)

            //Ice Candidate情報を追加する
            addIceCandidate(candidate)

        //offerを受け取った時の処理
        case "offer":

            LOG("Received offer ...")
            let offer = RTCSessionDescription(
                type: RTCSessionDescription.type(for: type),
                sdp: jsonMessage["sdp"].stringValue)
            setOffer(offer)

        //closeを受け取った時の処理
        case "close":
            LOG("peer is closed ...")
            hangUp()
        default:
            return
        }
    }

    //WebSocketからのデータ受信ができた際に呼ばれるメソッド
    func websocketDidReceiveData(socket: WebSocket, data: Data) {
 
        //ログ出力
        LOG("data.count: \(data.count)")
    }
    
    /********************
     * MARK: - RTCPeerConnectionDelegate ※使わないものもあるけど書いておかないとエラーになる
     ********************/
    
    //接続情報交換の状況が変化した際に呼ばれるメソッド
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
    }
    
    //映像/音声が追加された際に呼ばれるメソッド
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
 
        //ログ出力
        LOG("peer.onaddstream()")
        
        //メインスレッドで実行
        DispatchQueue.main.async(execute: { () -> Void in
            
            //ビデオのトラックが存在するならば、ビデオのトラックを取り出してremoteVideoViewに紐づける
            if stream.videoTracks.count > 0 {
                
                //ビデオのトラックを取り出して、remoteVideoViewに紐づける
                self.remoteVideoTrack = stream.videoTracks[0]
                self.remoteVideoTrack?.add(self.remoteVideoView)
            }
        })

    }

    //映像/音声削除された際に呼ばれるメソッド
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }

    //接続情報の交換が必要になった際に呼ばれるメソッド
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    }

    //PeerConnectionの接続状況が変化した際に呼ばれるメソッド
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {

        //接続状況が変化をログに表示する(失敗した際は切断も行うようにする)
        var state = ""
        switch (newState) {
            case RTCIceConnectionState.checking:
                state = "checking"
            case RTCIceConnectionState.completed:
                state = "completed"
            case RTCIceConnectionState.connected:
                state = "connected"
            case RTCIceConnectionState.closed:
                state = "closed"
                hangUp()
            case RTCIceConnectionState.failed:
                state = "failed"
                hangUp()
            case RTCIceConnectionState.disconnected:
                state = "disconnected"
            default:
                break
        }

        //ログ出力
        LOG("ICE connection Status has changed to \(state)")
    }

    //接続先候補の探索状況が変化した際に呼ばれるメソッド
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    }
    
    //Candidate(自分への接続先候補情報)が生成された際に呼ばれるメソッド
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {

        //候補先情報が取得はsdpMidプロパティで判断する
        if candidate.sdpMid != nil {

            //候補先情報が取得できたらIce Candidate情報をセットする
            sendIceCandidate(candidate)

        } else {

            //ログ出力
            LOG("empty ice event")
        }
    }

    //DataChannelが作られた際に呼ばれるメソッド
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    }

    //Candidateが削除された際に呼ばれるメソッド
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
    }
    
    /********************
     * MARK: - RTCEAGLVideoViewDelegate
     ********************/

    //ビデオのアスペクト比の調整をするメソッド
    func videoView(_ videoView: RTCEAGLVideoView, didChangeVideoSize size: CGSize) {
        let width = self.view.frame.width
        let height = self.view.frame.width * size.height / size.width
        videoView.frame = CGRect(
            x: 0,
            y: (self.view.frame.height - height) / 2,
            width: width,
            height: height
        )
    }

    /********************
     * MARK: - Fileprivate functions
     ********************/

    //Answerを受け取って受け取ったSDPを相手のSDPとして設定するメソッド
    fileprivate func setAnswer(_ answer: RTCSessionDescription) {

        //peerConnectionがnilの時は処理を終了する
        if peerConnection == nil {

            //ログ出力
            LOG("PeerConnection not exist!")
            return
        }

        //受け取ったSDPを相手のSDPとして設定
        self.peerConnection.setRemoteDescription(answer, completionHandler: { (error: Error?) in

            //ログ出力
            if error == nil {
                self.LOG("setRemoteDescription(answer) succsess")
            } else {
                self.LOG("setRemoteDescription(answer) ERROR: " + error.debugDescription)
            }
        })
    }

    //Ice Candidateを受け取ってWebSocketへ送るメソッド
    fileprivate func sendIceCandidate(_ candidate: RTCIceCandidate) {

        //ログ出力
        LOG("Sending ICE candidate.")

        //JSON形式でWebSocketへ送信するIce Candidateの情報を作成する
        let jsonCandidate: JSON = [
            "type": "candidate",
            "ice": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid!
            ]
        ]

        //送信用のメッセージデータを文字列へ変換する
        let message = jsonCandidate.rawString()!

        //ログ出力
        LOG("sending candidate=" + message)
        
        //WebSocketへIce Candidateの情報を送信する
        websocket.write(string: message)
    }
    
    //Ice Candidate情報をpeerConnectionインスタンスへの追加処理を行うメソッド
    fileprivate func addIceCandidate(_ candidate: RTCIceCandidate) {
        
        //peerConnectionインスタンスがnilでなければpeerConnectionのaddメソッドでIce Candidateデータを追加する
        if peerConnection != nil {
            peerConnection.add(candidate)
        } else {

            //ログ出力
            LOG("PeerConnection not exist!")
        }
    }

    //Offer情報のセットを行うメソッド
    fileprivate func setOffer(_ offer: RTCSessionDescription) {

        //peerConnectionインスタンスがあるかの確認
        if peerConnection != nil {

            //ログ出力
            LOG("PeerConnection alreay exist!")
        }

        //peerConnectionを生成する
        peerConnection = prepareNewConnection()

        //接続を試みる
        peerConnection.setRemoteDescription(offer, completionHandler: {(error: Error?) in

            //setRemoteDescriptionが成功したらAnswerを作る
            if error == nil {
                self.LOG("SetRemoteDescription(offer) succsess")
                self.makeAnswer()
            } else {
                self.LOG("SetRemoteDescription(offer) ERROR: " + error.debugDescription)
            }
        })
    }

    //Answer情報の作成を行うメソッド
    fileprivate func makeAnswer() {

        //ログ出力
        LOG("sending Answer. Creating remote session description...")

        //peerConnectionインスタンスがなければ何もしない
        if peerConnection == nil {
            LOG("peerConnection NOT exist!")
            return
        }

        //これはなにをやっているんだ...?
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        //Answer情報更新の結果を元に処理をするコールバックメソッド
        let answerCompletion = { (answer: RTCSessionDescription?, error: Error?) in
  
            //エラー発生時は何も返さずに処理を終了
            if error != nil { return }

            //ログ出力
            self.LOG("createAnswer() succsess")

            //相手にSDP情報を送るためのコールバックメソッド
            let setLocalDescCompletion = { (error: Error?) in
                
                //エラー発生時は何も返さずに処理を終了
                if error != nil { return }
                
                //ログ出力
                self.LOG("setLocalDescription() succsess")

                //相手に送る
                self.sendSDP(answer!)
            }

            //setLocalDescription作成を行う
            self.peerConnection.setLocalDescription(answer!, completionHandler: setLocalDescCompletion)
        }

        //Answerを生成を行う
        self.peerConnection.answer(for: constraints, completionHandler: answerCompletion)
    }

    //SDP情報を送信するメソッド
    fileprivate func sendSDP(_ desc: RTCSessionDescription) {
        
        //ログ出力
        LOG("Sending sdp...")
        
        //JSON形式でWebSocketへ送信するSDP情報を作成する
        let jsonSdp: JSON = [
            "sdp": desc.sdp, //SDP本体
            "type": RTCSessionDescription.string(for: desc.type) //offer or answerの情報
        ]

        //送信用のメッセージデータを文字列へ変換する
        let message = jsonSdp.rawString()!

        //ログ出力
        LOG("sending SDP=" + message)

        //WebSocketへ相手へ情報を送信する
        websocket.write(string: message)
    }
    
    //新しいPeerConnection作成用のメソッド
    fileprivate func prepareNewConnection() -> RTCPeerConnection {

        //STUN/TURNサーバーの指定
        let configuration = RTCConfiguration()
        configuration.iceServers = [RTCIceServer.init(urlStrings: ["stun:stun.l.google.com:19302"])]

        //PeerConectionの設定(今回はなし)
        let peerConnectionConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        //PeerConnectionの初期化
        peerConnection = peerConnectionFactory.peerConnection(with: configuration, constraints: peerConnectionConstraints, delegate: self)

        //音声トラックの作成
        let localAudioTrack = peerConnectionFactory.audioTrack(with: audioSource!, trackId: "ARDAMSa0")

        //PeerConnectionからAudioのSenderを作成
        let audioSender = peerConnection.sender(withKind: kRTCMediaStreamTrackKindAudio, streamId: "ARDAMS")

        //Senderにトラックを設定
        audioSender.track = localAudioTrack
        
        //映像トラックの作成
        let localVideoTrack = peerConnectionFactory.videoTrack(with: videoSource!, trackId: "ARDAMSv0")

        //PeerConnectionからVideoのSenderを作成
        let videoSender = peerConnection.sender(withKind: kRTCMediaStreamTrackKindVideo, streamId: "ARDAMS")

        //Senderにトラックを設定
        videoSender.track = localVideoTrack

        return peerConnection
    }

    //PeerConnectionの切断を行うメソッド
    fileprivate func hangUp() {

        //peerConnectionインスタンスがある場合のみ処理を実行する
        if peerConnection != nil {

            //RTCIceConnectionStateのenum値は`closed`の場合にはpeerConnectionを切断する
            if peerConnection.iceConnectionState != RTCIceConnectionState.closed {

                //peerConnectionを切断
                peerConnection.close()

                //ログ出力
                LOG("Sending close message.")

                //websocket側にも切断することを伝える
                let jsonClose: JSON = ["type": "close"]
                websocket.write(string: jsonClose.rawString()!)
            }

            //VideoTrackデータも削除する
            if remoteVideoTrack != nil {
                remoteVideoTrack?.remove(remoteVideoView)
            }

            //インスタンス格納用メンバ変数をnilにする
            remoteVideoTrack = nil
            peerConnection = nil
            
            //ログ出力
            LOG("PeerConnection is closed.")
        }
    }

    //PeerConnectionを生成から相手にOfferを送るための準備をする
    fileprivate func makeOffer() {
        
        //PeerConnectionを生成
        peerConnection = prepareNewConnection()

        //Offerの設定:今回は映像も音声も受け取る
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ], optionalConstraints: nil)

        //Offerの生成が完了した際の処理
        let offerCompletion = { (offer: RTCSessionDescription?, error: Error?) in
            
            //エラー発生時は何も返さずに処理を終了
            if error != nil { return }
            
            //ログ出力
            self.LOG("createOffer() succsess")

            //setLocalDescCompletionが完了した際の処理
            let setLocalDescCompletion = { (error: Error?) in

                //エラー発生時は何も返さずに処理を終了
                if error != nil { return }
                
                //ログ出力
                self.LOG("setLocalDescription() succsess")

                //相手に送る
                self.sendSDP(offer!)
            }

            //生成したOfferを自分のSDPとして設定
            self.peerConnection.setLocalDescription(offer!, completionHandler: setLocalDescCompletion)
        }

        //Offerを生成
        self.peerConnection.offer(for: constraints, completionHandler: offerCompletion)
    }
    
    //音声と映像に関する設定メソッド
    fileprivate func startVideo() {

        //音声ソースの生成と設定
        let audioSourceConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        audioSource = peerConnectionFactory.audioSource(with: audioSourceConstraints)
        
        //映像ソースの生成と設定
        let videoSourceConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        videoSource = peerConnectionFactory.avFoundationVideoSource(with: videoSourceConstraints)
        
        //映像ソースをプレビューに設定する
        cameraPreview.captureSession = videoSource?.captureSession
    }
    
    //デバッグログ出力：メソッドと行数・レスポンスデータを表示する
    fileprivate func LOG(_ body: String = "", function: String = #function, line: Int = #line) {

        //ログ出力
        print("[\(function) : \(line)] \(body)")
    }
}
